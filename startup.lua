-- ============================================================================
--  Exelia OS - startup.lua
--  Lanceur. Si les composants du systeme sont absents (premiere installation),
--  il telecharge tout depuis GitHub et place chaque fichier au bon endroit,
--  puis demarre le systeme :
--    System/run/ressource_loader.lua   systeme de fichiers, programmes, ExeliaScript
--    System/run/display.lua            affichage
--    System/run/fundamental_apps.lua   terminal, explorateur, parametres, MAJ, infos
--    System/run/main.lua               processus principal
-- ============================================================================
if not term.isColor() then
  print("Exelia OS necessite un ordinateur avance (ecran couleur).")
  return
end

local MODULES = { "ressource_loader", "display", "fundamental_apps", "main" }
local REPOS = {                       -- depot du projet (branche principale)
  "https://raw.githubusercontent.com/Archie442/ExeliaOS/main/",
  "https://raw.githubusercontent.com/Archie442/ExeliaOS/master/",
}
local UPDATE_CFG = "System/config/update.cfg"

-- ---------------------------------------------------- premiere installation --
local function systemMissing()
  for _, name in ipairs(MODULES) do
    if not fs.exists("System/run/" .. name .. ".lua") then return true end
  end
  return false
end

local function bootstrap()
  local w, h = term.getSize()
  local function screen(msg, frac, isError)
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    local title, sub = "Exelia OS", "Premiere installation"
    term.setCursorPos(math.floor((w - #title) / 2) + 1, math.floor(h / 2) - 3); term.write(title)
    term.setTextColor(colors.lightGray)
    term.setCursorPos(math.floor((w - #sub) / 2) + 1, math.floor(h / 2) - 2); term.write(sub)
    local bw = math.min(30, w - 4)
    local bx = math.floor((w - bw) / 2) + 1
    term.setCursorPos(bx, math.floor(h / 2)); term.setBackgroundColor(colors.gray); term.write(string.rep(" ", bw))
    term.setCursorPos(bx, math.floor(h / 2)); term.setBackgroundColor(isError and colors.red or colors.white)
    term.write(string.rep(" ", math.floor(bw * math.max(0, math.min(1, frac)))))
    term.setBackgroundColor(colors.black)
    term.setTextColor(isError and colors.red or colors.gray)
    msg = tostring(msg)
    local line = 1
    while #msg > 0 and line <= 4 do
      term.setCursorPos(2, math.floor(h / 2) + 1 + line)
      term.write(msg:sub(1, w - 2))
      msg = msg:sub(w - 1)
      line = line + 1
    end
  end
  local function fail(msg)
    screen(msg .. " Appuyez sur une touche.", 1, true)
    os.pullEventRaw("key")
    os.reboot()
    while true do sleep(1) end
  end
  local function get(url)
    local ok, r, err = pcall(http.get, url .. "?cb=" .. os.epoch("utc"))
    if not ok or not r then return nil, tostring(ok and err or r) end
    local body = r.readAll()
    r.close()
    if not body or body == "" then return nil, "reponse vide" end
    return body
  end

  if not http then fail("Le module HTTP est desactive : activez-le dans la configuration de ComputerCraft.") end

  -- depot : celui du fichier de configuration s'il existe, sinon ceux par defaut
  local bases = {}
  if fs.exists(UPDATE_CFG) then
    local f = fs.open(UPDATE_CFG, "r")
    local cfg = f and textutils.unserialize(f.readAll())
    if f then f.close() end
    if type(cfg) == "table" and type(cfg.repo) == "string" then
      bases[1] = cfg.repo:sub(-1) == "/" and cfg.repo or (cfg.repo .. "/")
    end
  end
  for _, r in ipairs(REPOS) do bases[#bases + 1] = r end

  screen("Recherche du depot...", 0.02)
  local base, manifest, lastErr
  for _, b in ipairs(bases) do
    local body, err = get(b .. "manifest.json")
    local m = body and textutils.unserializeJSON(body)
    if type(m) == "table" and type(m.files) == "table" then base, manifest = b, m break end
    lastErr = body and "manifeste invalide" or err
  end
  if not manifest then fail("Depot introuvable (" .. tostring(lastErr) .. ").") end

  local files, n = {}, #manifest.files
  for i, path in ipairs(manifest.files) do
    if type(path) ~= "string" or path:find("%.%.") or path:find("^/") then fail("Fichier refuse : " .. tostring(path)) end
    if path ~= "startup.lua" then       -- le lanceur est deja en place
      screen("Telechargement : " .. path, 0.05 + 0.85 * (i - 1) / math.max(1, n))
      local code, err = get(base .. path)
      if not code then fail("Echec : " .. path .. " (" .. tostring(err) .. ").") end
      if path:match("%.lua$") and not load(code, "=" .. path) then fail("Fichier corrompu : " .. path .. ".") end
      files[#files + 1] = { path = path, code = code }
    end
  end

  screen("Installation des fichiers...", 0.92)
  for _, f in ipairs(files) do
    local dir = fs.getDir(f.path)
    if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
    local o = fs.open(f.path, "w")
    if not o then fail("Ecriture impossible : " .. f.path .. ".") end
    o.write(f.code); o.close()
  end
  for _, d in ipairs({ "System/config", "Programs", "ProgramsData", "User/Documents", "User/Desktop" }) do
    if not fs.exists(d) then fs.makeDir(d) end
  end
  if not fs.exists(UPDATE_CFG) then
    local o = fs.open(UPDATE_CFG, "w")
    if o then o.write(textutils.serialize({ repo = base })); o.close() end
  end
  screen("Installation terminee !", 1)
  sleep(1)
end

if systemMissing() then bootstrap() end

-- ---------------------------------------------------------------- demarrage --
local X = {
  VERSION = "4.0",
  NAME = "Exelia OS",
  fs = fs,                         -- vrai systeme de fichiers (reserve au systeme)
  unpack = table.unpack or unpack,
  native = term.native(),
  S = {},                          -- etat partage (fenetre active, verrouillage...)
  wins = {},                       -- fenetres ouvertes
  notifs = {},                     -- notifications a l'ecran
  appList = {},                    -- applications disponibles
  cfg = { user = nil, pass = "", wall = 1, clock24 = true },
}
X.W, X.H = X.native.getSize()

-- Restaure la version precedente si le demarrage echoue juste apres une mise a jour
local function recover()
  local backup, pending = "System/config/backup", "System/config/update.pending"
  if not fs.exists(pending) or not fs.isDir(backup) then return false end
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
        if o then o.write(data); o.close() end
      end
    end
  end
  walk("")
  fs.delete(pending)
  return true
end

local ok, err = pcall(function()
  for _, name in ipairs(MODULES) do
    local path = "System/run/" .. name .. ".lua"
    local fn, e = loadfile(path)
    if not fn then error("Chargement de " .. path .. " impossible : " .. tostring(e), 0) end
    fn(X)
  end
  X.start()
end)

if not ok then
  if X.restorePalette then pcall(X.restorePalette) end
  term.redirect(term.native())
  term.setBackgroundColor(colors.blue); term.setTextColor(colors.white); term.clear()
  term.setCursorPos(2, 2); print("Exelia OS - erreur systeme")
  term.setCursorPos(2, 4); print(tostring(err))
  print()
  local restored = false
  if not X.booted then restored = recover() end
  print(restored and "  Version precedente restauree. Redemarrage..." or "  Appuyez sur une touche pour redemarrer.")
  if restored then sleep(2) else os.pullEventRaw("key") end
  os.reboot()
end
