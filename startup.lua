
-- ============================================================================
-- Exelia OS - startup.lua
-- Lanceur + installateur automatique
-- ============================================================================

if not term.isColor() then
    print("Exelia OS necessite un ordinateur avance (ecran couleur).")
    return
end

local REPO = "https://raw.githubusercontent.com/Archie442/ExeliaOS/main/"
local API = "https://api.github.com/repos/Archie442/ExeliaOS/git/trees/main?recursive=1"

-- ============================================================================
-- OUTILS
-- ============================================================================

local function encodePath(path)
    return path:gsub("([^%w%-_%.~/])", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function download(url)
    local response, err = http.get(url, {
        ["User-Agent"] = "ExeliaOS",
        ["Accept"] = "application/vnd.github+json"
    })

    if not response then
        return nil, tostring(err or "Connexion impossible")
    end

    local code = response.getResponseCode()
    local content = response.readAll()
    response.close()

    if code < 200 or code >= 300 then
        return nil, "Erreur HTTP " .. tostring(code)
    end

    return content
end

local function writeFile(path, content)
    local parent = fs.getDir(path)

    if parent ~= "" then
        if fs.exists(parent) and not fs.isDir(parent) then
            return false, "Un fichier bloque le dossier : " .. parent
        end

        if not fs.exists(parent) then
            fs.makeDir(parent)
        end
    end

    if fs.exists(path) then
        if fs.isDir(path) then
            return false, "Un dossier bloque le fichier : " .. path
        end
        return true
    end

    local file, err = fs.open(path, "w")

    if not file then
        return false, "Impossible de creer " .. path .. " : " .. tostring(err)
    end

    local ok, writeError = pcall(function()
        file.write(content)
        file.close()
    end)

    if not ok then
        pcall(function() file.close() end)

        if fs.exists(path) then
            fs.delete(path)
        end

        return false, "Erreur d'ecriture : " .. tostring(writeError)
    end

    return true
end

-- ============================================================================
-- INSTALLATEUR
-- ============================================================================

local function install()

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 2)

    print("Exelia OS")
    print("Installation automatique")
    print("------------------------------")

    if not http then
        return false, "HTTP indisponible."
    end

    -- Recuperation de l'arborescence GitHub

    print("Connexion a GitHub...")

    local data, err = download(API)

    if not data then
        return false, err
    end

    local decoded, tree = pcall(textutils.unserializeJSON, data)

    if not decoded or type(tree) ~= "table" or type(tree.tree) ~= "table" then
        return false, "Impossible de lire l'arborescence GitHub."
    end

    if tree.truncated then
        return false, "Depot trop volumineux pour une installation complete."
    end

    local files = {}

    for _, entry in ipairs(tree.tree) do
        if entry.type == "blob" and entry.path ~= "startup.lua" then
            files[#files + 1] = entry.path
        end
    end

    local total = #files
    local installed = 0
    local skipped = 0

    print("Fichiers trouves : " .. total)
    print()

    -- Telechargement des fichiers

    for i, path in ipairs(files) do

        term.setCursorPos(2, 7)
        term.clearLine()
        term.setTextColor(colors.lightBlue)
        print("[" .. i .. "/" .. total .. "] " .. path)

        if fs.exists(path) then
            skipped = skipped + 1
        else
            local content, downloadError = download(REPO .. encodePath(path))

            if not content then
                return false, "Telechargement impossible : " .. path
                    .. "\n" .. tostring(downloadError)
            end

            local success, writeError = writeFile(path, content)

            if not success then
                return false, writeError
            end

            installed = installed + 1
        end

        term.setCursorPos(2, 9)
        term.setTextColor(colors.white)
        term.clearLine()
        print("Installation : " .. math.floor(i / math.max(total, 1) * 100) .. "%")
    end

    term.setCursorPos(2, 11)
    term.setTextColor(colors.lime)
    print("Installation terminee !")

    print()
    print("Nouveaux fichiers : " .. installed)
    print("Fichiers existants : " .. skipped)

    sleep(2)

    return true
end

-- ============================================================================
-- LANCEMENT DE L'INSTALLATEUR
-- ============================================================================

local success, installError = install()

if not success then

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(2, 2)

    print("Exelia OS - Erreur d'installation")
    print("------------------------------")
    print()
    print(tostring(installError))
    print()
    term.setTextColor(colors.white)
    print("Verifiez votre connexion Internet.")
    print("Appuyez sur une touche pour quitter.")

    os.pullEventRaw("key")
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
-- RESTAURATION
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
            local source = fs.combine(backup, rel)

            if fs.isDir(source) then
                walk(rel)
            else

                local f = fs.open(source, "r")
                local data = f and f.readAll()

                if f then
                    f.close()
                end

                if data then
                    local parent = fs.getDir(rel)

                    if parent ~= "" and not fs.exists(parent) then
                        fs.makeDir(parent)
                    end

                    local output = fs.open(rel, "w")

                    if output then
                        output.write(data)
                        output.close()
                    end
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

local ok, err = pcall(function()

    for _, name in ipairs(MODULES) do

        local path = "System/run/" .. name .. ".lua"

        local fn, loadError = loadfile(path)

        if not fn then
            error(
                "Chargement de " .. path .. " impossible : "
                .. tostring(loadError),
                0
            )
        end

        fn(X)
    end

    X.start()

end)

-- ============================================================================
-- GESTION DES ERREURS
-- ============================================================================

if not ok then

    if X.restorePalette then
        pcall(X.restorePalette)
    end

    term.redirect(term.native())

    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(2, 2)

    print("Exelia OS - Erreur systeme")
    print("------------------------------")
    print()
    print(tostring(err))
    print()

    local restored = false

    if not X.noRecover then
        restored = recover()
    end

    if restored then
        print("Version precedente restauree.")
        print("Redemarrage...")
        sleep(2)
        os.reboot()
    else
        print("Appuyez sur une touche pour quitter.")
        os.pullEventRaw("key")
    end
end
