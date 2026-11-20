-- ============================================================================
--  Exelia OS - startup.lua
--  Lanceur : charge les composants systeme situes dans System/run/ puis demarre.
--    System/run/ressource_loader.lua   systeme de fichiers, programmes, ExeliaScript
--    System/run/display.lua            affichage
--    System/run/fundamental_apps.lua   terminal, explorateur, parametres, MAJ, infos
--    System/run/main.lua               processus principal
-- ============================================================================
if not term.isColor() then
  print("Exelia OS necessite un ordinateur avance (ecran couleur).")
  return
end

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

local MODULES = { "ressource_loader", "display", "fundamental_apps", "main" }

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
