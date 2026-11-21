-- ============================================================================
--  Exelia OS - install.lua
--  Sur un ordinateur AVANCE, avec HTTP active :
--    wget run https://raw.githubusercontent.com/Archie442/ExeliaOS/main/install.lua
--  Il telecharge startup.lua puis redemarre : au premier lancement, startup.lua
--  telecharge tous les autres fichiers et les place au bon endroit.
--  (Vous pouvez aussi poser startup.lua seul sur l'ordinateur : meme resultat.)
-- ============================================================================
local BASES = {
  "https://raw.githubusercontent.com/Archie442/ExeliaOS/main/",
  "https://raw.githubusercontent.com/Archie442/ExeliaOS/master/",
}

if not term.isColor() then error("Exelia OS necessite un ordinateur avance.", 0) end
if not http then error("Le module HTTP est desactive.", 0) end

print("Installation d'Exelia OS...")
local data
for _, base in ipairs(BASES) do
  local r = http.get(base .. "startup.lua?cb=" .. os.epoch("utc"))
  if r then data = r.readAll(); r.close() end
  if data and #data > 100 then break end
end
if not data or #data <= 100 then error("Depot injoignable : verifiez votre connexion.", 0) end

local f = fs.open("startup.lua", "w")
if not f then error("Ecriture de startup.lua impossible.", 0) end
f.write(data)
f.close()

print("Redemarrage : le systeme termine l'installation...")
sleep(2)
os.reboot()
