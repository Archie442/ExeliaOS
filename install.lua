-- ============================================================================
--  Exelia OS - installateur
--  Sur un ordinateur AVANCE, avec HTTP active :
--    wget run https://raw.githubusercontent.com/exelia-os/exelia-os/main/install.lua
--  (adaptez BASE a l'adresse de votre depot GitHub)
-- ============================================================================
local BASE = "https://raw.githubusercontent.com/exelia-os/exelia-os/main/"

if not term.isColor() then error("Exelia OS necessite un ordinateur avance.", 0) end
if not http then error("Le module HTTP est desactive.", 0) end

local function get(path)
  local r, err = http.get(BASE .. path .. "?cb=" .. os.epoch("utc"))
  if not r then error("Telechargement impossible : " .. path .. " (" .. tostring(err) .. ")", 0) end
  local d = r.readAll()
  r.close()
  return d
end

print("Installation d'Exelia OS...")
local man = textutils.unserializeJSON(get("manifest.json"))
if type(man) ~= "table" or type(man.files) ~= "table" then error("Manifeste invalide.", 0) end

for i, path in ipairs(man.files) do
  write(string.format("[%d/%d] %s\n", i, #man.files, path))
  local data = get(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  if not f then error("Ecriture impossible : " .. path, 0) end
  f.write(data)
  f.close()
end

for _, d in ipairs({ "System/config", "Programs", "ProgramsData", "User/Documents", "User/Desktop" }) do
  if not fs.exists(d) then fs.makeDir(d) end
end
local f = fs.open("System/config/update.cfg", "w")
f.write(textutils.serialize({ repo = BASE }))
f.close()

print("Termine ! Redemarrage...")
sleep(2)
os.reboot()
