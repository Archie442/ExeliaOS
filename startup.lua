
-- ============================================================================
-- Exelia OS - startup.lua
-- Lanceur et installateur automatique
-- ============================================================================

local REPO = "https://raw.githubusercontent.com/Archie442/ExeliaOS/main/"
local API = "https://api.github.com/repos/Archie442/ExeliaOS/git/trees/main?recursive=1"

if not term.isColor() then
    print("Exelia OS necessite un ordinateur avance (ecran couleur).")
    return
end

-- ============================================================================
-- INSTALLATION AUTOMATIQUE
-- ============================================================================

local function install()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 2)

    print("Exelia OS - Installation")
    print("------------------------------")
    print("Verification des fichiers...")

    if not http then
        return false, "HTTP indisponible."
    end

    local function request(url)
        local response, err = http.get(url, nil, true)

        if not response then
            return nil, err or "Erreur HTTP"
        end

        local code = response.getResponseCode()
        local data = response.readAll()
        response.close()

        if code < 200 or code >= 300 then
            return nil, "HTTP " .. tostring(code)
        end

        return data
    end

    -- Recuperation de la liste complete des fichiers du depot
    local data, err = request(API)

    if not data then
        return false, "Impossible de contacter GitHub : " .. tostring(err)
    end

    local success, tree = pcall(textutils.unserializeJSON, data)

    if not success or type(tree) ~= "table" or type(tree.tree) ~= "table" then
        return false, "Reponse GitHub invalide."
    end

    local files = {}

    for _, entry in ipairs(tree.tree) do
        if entry.type == "blob" and entry.path ~= "startup.lua" then
            files[#files + 1] = entry.path
        end
    end

    local installed = 0
    local total = #files

    for i, path in ipairs(files) do
        if not fs.exists(path) then
            local parent = fs.getDir(path)

            if parent ~= "" and not fs.exists(parent) then
                fs.makeDir(parent)
            end

            term.setCursorPos(2, 6)
            term.clearLine()
            print("Telechargement : " .. path)

            local content, downloadError = request(REPO .. path)

            if not content then
                return false, "Erreur sur " .. path .. " : " .. tostring(downloadError)
            end

            local temp = path .. ".exelia_tmp"
            local file = fs.open(temp, "w")

            if not file then
                return false, "Impossible de creer : " .. path
            end

            file.write(content)
            file.close()

            if fs.getSize(temp) == 0 then
                fs.delete(temp)
                return false, "Fichier vide : " .. path
            end

            fs.move(temp, path)
            installed = installed + 1
        end

        term.setCursorPos(2, 8)
        term.clearLine()
        print("Progression : " .. i .. "/" .. total)
    end

    term.setCursorPos(2, 10)
    print("Installation terminee !")
    print(installed .. " fichier(s) installe(s).")

    sleep(1.5)
    return true
end

local ok, installError = install()

if not ok then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(2, 2)
    print("Exelia OS - Erreur d'installation")
    print()
    print(tostring(installError))
    print()
    print("Verifiez votre connexion Internet.")
    print("Appuyez sur une touche pour redemarrer.")
    os.pullEventRaw("key")
    os.reboot()
    return
end

-- ============================================================================
-- INITIALISATION DU SYSTEME
-- ============================================================================

local X = {
    VERSION = "4.0",
    NAME = "Exelia OS",
    fs = fs,
    unpack = table.unpack or unpack,
    native = term.native(),
    S = {},
    wins = {},
    notifs = {},
    appList = {},
    cfg = {
        user = nil,
        pass = "",
        wall = 1,
        clock24 = true
    },
}

X.W, X.H = X.native.getSize()

local MODULES = {
    "ressource_loader",
    "display",
    "fundamental_apps",
    "main"
}

-- ============================================================================
-- RECUPERATION APRES UNE MISE A JOUR RATEE
-- ============================================================================

local function recover()
    local backup = "System/config/backup"
    local pending = "System/config/update.pending"

    if not fs.exists(pending) or not fs.isDir(backup) then
        return false
    end

    local function walk(dir)
        for _, name in ipairs(fs.list(fs.combine(backup, dir))) do
            local rel = fs.combine(dir, name)

            if fs.isDir(fs.combine(backup, rel)) then
                walk(rel)
            else
                local f = fs.open(fs.combine(backup, rel), "r")
                local data = f and f.readAll()

                if f then f.close() end

                local o = data and fs.open(rel, "w")

                if o then
                    o.write(data)
                    o.close()
                end
            end
        end
    end

    walk("")
    fs.delete(pending)

    return true
end

-- ============================================================================
-- DEMARRAGE
-- ============================================================================

local success, err = pcall(function()
    for _, name in ipairs(MODULES) do
        local path = "System/run/" .. name .. ".lua"

        local fn, e = loadfile(path)

        if not fn then
            error("Chargement de " .. path .. " impossible : " .. tostring(e), 0)
        end

        fn(X)
    end

    X.start()
end)

if not success then
    if X.restorePalette then
        pcall(X.restorePalette)
    end

    term.redirect(term.native())
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 2)

    print("Exelia OS - erreur systeme")
    term.setCursorPos(2, 4)
    print(tostring(err))
    print()

    local restored = false

    if not X.noRecover then
        restored = recover()
    end

    print(restored
        and "Version precedente restauree. Redemarrage..."
        or "Appuyez sur une touche pour redemarrer.")

    if restored then
        sleep(2)
    else
        os.pullEventRaw("key")
    end

    os.reboot()
end
