-- ============================================================================
--  Exelia OS - System/run/ressource_loader.lua
--  Gere le systeme de fichiers : structure des dossiers, configuration,
--  acces restreint de l'utilisateur (/User), programmes installes et lecture
--  des applications ExeliaScript (.as).
-- ============================================================================
local X = ...
local fs, S, cfg, appList, unpack = X.fs, X.S, X.cfg, X.appList, X.unpack
local VERSION = X.VERSION

-- ---------------------------------------------------------------- chemins --
local CFG_DIR        = "System/config"           -- fichiers de configuration
local RUN_DIR        = "System/run"              -- composants du systeme
local INTEGRATED_DIR = "System/IntegratedApps"   -- applications integrees (.as)
local PROGRAMS_DIR   = "Programs"                -- Programs/<id>/<id>.as
local DATA_DIR       = "ProgramsData"            -- ProgramsData/<id>/*.dg
local USER_DIR       = "User"                    -- seul dossier visible par l'utilisateur
local CFG_FILE       = CFG_DIR .. "/config"
local PROGRAMS_DB    = CFG_DIR .. "/programs"
local UPDATE_CFG     = CFG_DIR .. "/update.cfg"
local BACKUP_DIR     = CFG_DIR .. "/backup"
local PENDING_FILE   = CFG_DIR .. "/update.pending"
local STORE_CODE     = "MBLQ7iyu"                -- catalogue public (JSON) sur Pastebin
local STORE_URL      = "https://pastebin.com/raw/" .. STORE_CODE
local DEFAULT_REPO   = "https://raw.githubusercontent.com/exelia-os/exelia-os/main/"

-- ------------------------------------------------------------- fichiers --
local function readFile(p)
  local f = fs.open(p, "r")
  if not f then return nil end
  local d = f.readAll(); f.close()
  return d
end
local function writeFile(p, d)
  local f = fs.open(p, "w")
  if not f then return false end
  f.write(d); f.close()
  return true
end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function stamp() return (os.epoch and os.epoch("utc")) or math.floor(os.clock() * 1000) end

-- Cree l'arborescence du systeme si necessaire
local function ensureStructure()
  for _, d in ipairs({ CFG_DIR, RUN_DIR, INTEGRATED_DIR, PROGRAMS_DIR, DATA_DIR,
                       USER_DIR .. "/Documents", USER_DIR .. "/Desktop" }) do
    if not fs.exists(d) then pcall(fs.makeDir, d) end
  end
  if not fs.exists(UPDATE_CFG) then
    writeFile(UPDATE_CFG, textutils.serialize({ repo = DEFAULT_REPO }))
  end
end

-- ---------------------------------------------------------- configuration --
local function loadCfg()
  local d = fs.exists(CFG_FILE) and readFile(CFG_FILE) or nil
  local t = d and textutils.unserialize(d)
  if type(t) == "table" then for k, v in pairs(t) do cfg[k] = v end end
end

local function saveCfg()
  pcall(fs.makeDir, CFG_DIR)
  writeFile(CFG_FILE, textutils.serialize(cfg))
end

-- Hachage simple du mot de passe (pas de SHA integre dans ComputerCraft)
local function hash(s)
  local a, b = 5381, 7919
  s = "exelia$" .. s .. "$" .. #s
  for i = 1, #s do
    local c = s:byte(i)
    a = (a * 33 + c) % 4294967291
    b = (b * 131 + c + a) % 4294967279
  end
  return a .. ":" .. b
end


local function verCmp(a, b)
  local pa, pb = {}, {}
  for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y and 1 or -1 end
  end
  return 0
end

-- ExeliaScript : l'operateur + concatene les chaines ("Score " + score).
-- Le preprocesseur remplace + par .. quand un texte litteral est a cote ;
-- le metatable des chaines gere les autres cas (variable + variable).
pcall(function()
  local mt = getmetatable("")
  if mt and not mt.__add then
    mt.__add = function(a, b) return tostring(a) .. tostring(b) end
  end
end)

-- fin d'un litteral (chaine ou [[...]]) qui commence en i, sinon nil
local function skipLiteral(src, i)
  local c = src:sub(i, i)
  if c == '"' or c == "'" then
    local j = i + 1
    while j <= #src do
      local d = src:sub(j, j)
      if d == "\\" then j = j + 2
      elseif d == c then return j
      else j = j + 1 end
    end
    return #src
  elseif c == "[" then
    local eq = src:match("^%[(=*)%[", i)
    if eq then
      local close = "]" .. eq .. "]"
      local e = src:find(close, i, true)
      return e and (e + #close - 1) or #src
    end
  end
  return nil
end

-- fin d'un commentaire qui commence en i (sur "--"), sinon nil
local function skipComment(src, i)
  if src:sub(i, i + 1) ~= "--" then return nil end
  local eq = src:match("^%-%-%[(=*)%[", i)
  if eq then
    local close = "]" .. eq .. "]"
    local e = src:find(close, i, true)
    return e and (e + #close - 1) or #src
  end
  local e = src:find("\n", i, true)
  return e and (e - 1) or #src
end

-- decoupe les arguments d'un appel ; i = position juste apres "("
local function splitArgs(src, i)
  local args, depth, start, k, n = {}, 0, i, i, #src
  while k <= n do
    local lit = skipLiteral(src, k)
    local com = (not lit) and skipComment(src, k)
    if lit then k = lit + 1
    elseif com then k = com + 1
    else
      local c = src:sub(k, k)
      if c == "(" or c == "[" or c == "{" then depth = depth + 1
      elseif c == ")" or c == "]" or c == "}" then
        if depth == 0 then
          args[#args + 1] = src:sub(start, k - 1)
          return args, k
        end
        depth = depth - 1
      elseif c == "," and depth == 0 then
        args[#args + 1] = src:sub(start, k - 1); start = k + 1
      end
      k = k + 1
    end
  end
  return nil
end

-- "scores.best" -> "scores.best", "best" (nom de la variable)
local function lvalue(s)
  s = s:match("^%s*(.-)%s*$")
  if s == "" or s == "nil" or s == "true" or s == "false" then return nil end
  if not s:match("^[%a_][%w_%.]*$") or s:find("%.%.") or s:sub(-1) == "." then return nil end
  return s, (s:match("([%w_]+)$"))
end

-- exelia.dataGroup.registerVariable("g", var) / .save(var, "g") recoivent une
-- *variable* : on la transforme en (nom, acces lecture, acces ecriture).
local function rewriteDataGroup(src)
  if not src:find("exelia.dataGroup.", 1, true) then return src end
  local out, i, n = {}, 1, #src
  while i <= n do
    local lit = skipLiteral(src, i)
    local com = (not lit) and skipComment(src, i)
    if lit then out[#out + 1] = src:sub(i, lit); i = lit + 1
    elseif com then out[#out + 1] = src:sub(i, com); i = com + 1
    else
      local handled = false
      local prev = i > 1 and src:sub(i - 1, i - 1) or ""
      if src:sub(i, i) == "e" and not prev:match("[%w_%.]") then
        for _, fname in ipairs({ "registerVariable", "save" }) do
          local head = "exelia.dataGroup." .. fname .. "("
          if src:sub(i, i + #head - 1) == head then
            local args, close = splitArgs(src, i + #head)
            if args and #args == 2 then
              local repl
              if fname == "registerVariable" then
                local v, key = lvalue(args[2])
                if v then
                  repl = head .. args[1] .. ', "' .. key .. '", function() return ' .. v ..
                         ' end, function(__v) ' .. v .. ' = __v end)'
                end
              else
                local v, key = lvalue(args[1])
                if v then
                  repl = head .. args[2] .. ', "' .. key .. '", function() return ' .. v .. ' end)'
                end
              end
              if repl then out[#out + 1] = repl; i = close + 1; handled = true; break end
            end
          end
        end
      end
      if not handled then out[#out + 1] = src:sub(i, i); i = i + 1 end
    end
  end
  return table.concat(out)
end

local function plusPass(src)
  local out, i, n = {}, 1, #src
  local prevString = false
  while i <= n do
    local c = src:sub(i, i)
    local lit = skipLiteral(src, i)
    local com = (not lit) and skipComment(src, i)
    if com then
      out[#out + 1] = src:sub(i, com); i = com + 1
    elseif lit then
      out[#out + 1] = src:sub(i, lit); i = lit + 1; prevString = true
    elseif c == "+" then
      local nxt = src:match("^%s*(.)", i + 1)
      local nextIsString = nxt == '"' or nxt == "'" or (nxt == "[" and src:match("^%s*%[=*%[", i + 1) ~= nil)
      out[#out + 1] = (prevString or nextIsString) and " .. " or "+"
      i = i + 1; prevString = false
    elseif c:match("%s") then
      out[#out + 1] = c; i = i + 1
    else
      out[#out + 1] = c; i = i + 1; prevString = false
    end
  end
  return table.concat(out)
end

local function preprocess(src)
  return plusPass(rewriteDataGroup(src))
end


-- ------------------------------------------------------------------ http --
local function sanitizeId(s)
  s = tostring(s):lower():gsub("[^%w_%-]", "_")
  s = s:gsub("^_+", ""):gsub("_+$", "")
  if s == "" then s = "app" end
  return s:sub(1, 32)
end

local function httpGetText(url)
  if not http then return nil, "Le module HTTP est indisponible." end
  if http.checkURL then
    local ok, why = http.checkURL(url)
    if not ok then return nil, "URL bloquee : " .. tostring(why) end
  end
  local r, err = http.get(url, { ["Cache-Control"] = "no-cache" })
  if not r then return nil, "Connexion impossible : " .. tostring(err) end
  local body = r.readAll()
  r.close()
  if not body or body == "" then return nil, "Reponse vide." end
  return body
end

-- Transforme un code Pastebin / lien en URL telechargeable
local function resolveSource(input)
  input = trim(tostring(input or ""))
  if input == "" then return nil end
  if input:match("^%w+$") and #input >= 6 and #input <= 12 then
    return "https://pastebin.com/raw/" .. input, "pastebin", input
  end
  local code = input:match("pastebin%.com/raw/(%w+)") or input:match("pastebin%.com/(%w+)")
  if code and code ~= "u" then return "https://pastebin.com/raw/" .. code, "pastebin", code end
  local user, repo, rest = input:match("github%.com/([^/]+)/([^/]+)/blob/(.+)")
  if user then return "https://raw.githubusercontent.com/" .. user .. "/" .. repo .. "/" .. rest, "url", input end
  if input:match("^https?://") then return input, "url", input end
  return nil
end

-- ------------------------------------------------ acces restreint : /User --
-- L'utilisateur (Explorateur, Terminal, Editeur, applications) voit /User comme
-- sa racine "/" : System, Programs, ProgramsData, rom et le reste n'existent pas.
local function vpath(p)                       -- chemin virtuel -> chemin reel
  if type(p) ~= "string" then return nil end
  local ok, n = pcall(fs.combine, "", p)
  if not ok or n == ".." or n:sub(1, 3) == "../" then return nil end
  return (n == "") and USER_DIR or (USER_DIR .. "/" .. n)
end

local function deny() error("Acces refuse", 3) end

local userFs = {
  combine = fs.combine, getName = fs.getName, getDir = fs.getDir,
  exists = function(p) local r = vpath(p); return r ~= nil and fs.exists(r) end,
  isDir = function(p) local r = vpath(p); return r ~= nil and fs.isDir(r) end,
  isReadOnly = function(p) local r = vpath(p); if not r then return true end return fs.isReadOnly(r) end,
  list = function(p) local r = vpath(p); if not r then deny() end return fs.list(r) end,
  open = function(p, m)
    local r = vpath(p)
    if not r then return nil, "Acces refuse" end
    return fs.open(r, m)
  end,
  makeDir = function(p) local r = vpath(p); if not r then deny() end return fs.makeDir(r) end,
  delete = function(p)
    local r = vpath(p)
    if not r or r == USER_DIR then deny() end
    return fs.delete(r)
  end,
  move = function(a, b)
    local ra, rb = vpath(a), vpath(b)
    if not ra or not rb or ra == USER_DIR then deny() end
    return fs.move(ra, rb)
  end,
  copy = function(a, b)
    local ra, rb = vpath(a), vpath(b)
    if not ra or not rb then deny() end
    return fs.copy(ra, rb)
  end,
  getSize = function(p) local r = vpath(p); if not r then deny() end return fs.getSize(r) end,
  getFreeSpace = function() return fs.getFreeSpace(USER_DIR) end,
  getCapacity = function() return fs.getCapacity and fs.getCapacity(USER_DIR) or nil end,
  getDrive = function() return "hdd" end,
  isDriveRoot = function() return false end,
  attributes = function(p)
    local r = vpath(p)
    if not r then deny() end
    return fs.attributes(r)
  end,
  find = function(w)
    local out = {}
    local ok, n = pcall(fs.combine, "", w)
    if not ok or n == ".." or n:sub(1, 3) == "../" then return out end
    for _, r in ipairs(fs.find(USER_DIR .. "/" .. n)) do out[#out + 1] = r:sub(#USER_DIR + 2) end
    return out
  end,
  complete = function(partial, path, ...)
    return fs.complete(partial, vpath(path) or USER_DIR, ...)
  end,
}

-- ------------------------------------------------ environnements d'execution --
-- Les programmes installes tournent dans un bac a sable : aucun acces au vrai
-- systeme de fichiers, a os.run, a shell, a io... Seul /User est visible.
local SAFE_GLOBALS = {
  "assert", "error", "ipairs", "next", "pairs", "pcall", "select", "setmetatable", "getmetatable",
  "tonumber", "tostring", "type", "unpack", "xpcall", "rawget", "rawset", "rawequal",
  "math", "string", "table", "coroutine", "textutils", "colors", "colours", "keys", "term",
  "window", "rednet", "peripheral", "http", "parallel", "sleep", "write", "print", "printError",
  "read", "vector", "bit", "bit32", "paintutils",
}
local SAFE_OS = {
  "time", "clock", "day", "epoch", "date", "startTimer", "cancelTimer", "setAlarm", "cancelAlarm",
  "queueEvent", "pullEvent", "pullEventRaw", "version", "getComputerID", "getComputerLabel",
}

local function sandboxEnv()
  local env = {}
  for _, k in ipairs(SAFE_GLOBALS) do env[k] = _G[k] end
  local o = {}
  for _, k in ipairs(SAFE_OS) do o[k] = os[k] end
  o.setComputerLabel = os.setComputerLabel
  o.reboot = function() X.sysReboot() end
  o.shutdown = function() X.sysShutdown() end
  env.os = o
  env.fs = userFs
  env._G = env
  local function ld(chunk, name, mode, e) return load(chunk, name, mode or "t", e or env) end
  env.load = ld
  env.loadstring = function(c, n) return ld(c, n) end
  env.loadfile = function(p, mode, e)
    local r = vpath(p)
    local src = r and fs.exists(r) and not fs.isDir(r) and readFile(r)
    if not src then return nil, "Fichier introuvable : " .. tostring(p) end
    return ld(src, "=" .. tostring(p), mode, e)
  end
  env.dofile = function(p)
    local f, e = env.loadfile(p)
    if not f then error(e, 2) end
    return f()
  end
  return env
end

-- ---------------------------------------------------- registre des programmes --
local function loadManifest()
  local d = fs.exists(PROGRAMS_DB) and readFile(PROGRAMS_DB) or nil
  local t = d and textutils.unserialize(d)
  return type(t) == "table" and t or {}
end
local function saveManifest(m)
  pcall(fs.makeDir, CFG_DIR)
  writeFile(PROGRAMS_DB, textutils.serialize(m))
end

local refreshApps

-- Installe un programme (code pastebin ou lien) dans Programs/<id>/<id>.as
local function installProgram(id, meta, src)
  id = sanitizeId(id)
  local url, kind, ref = resolveSource(src)
  if not url then return false, "Lien invalide." end
  local fetchUrl = url
  if kind == "pastebin" then fetchUrl = url .. "?cb=" .. stamp() end
  local code, err = httpGetText(fetchUrl)
  if not code then return false, err end
  if #code < 10 then return false, "Fichier trop court." end
  local fn, serr = load(preprocess(code), "=" .. id)
  if not fn then return false, "Erreur de syntaxe : " .. tostring(serr) end
  local minv = code:match('app%.minOsVersion%s*=%s*"?([%d%.]+)"?')
  if minv and verCmp(VERSION, minv) < 0 then
    return false, "Necessite Exelia OS " .. minv .. " ou plus recent (installe : " .. VERSION .. ")."
  end
  local dir = fs.combine(PROGRAMS_DIR, id)
  pcall(fs.makeDir, dir)
  local path = fs.combine(dir, id .. ".as")
  if not writeFile(path, code) then return false, "Ecriture impossible : " .. id end
  pcall(fs.makeDir, fs.combine(DATA_DIR, id))
  local m = loadManifest()
  m[id] = { name = meta.name or id, author = meta.author, description = meta.description, source = ref }
  saveManifest(m)
  refreshApps()
  return true, id
end

-- Desinstalle un programme (ses donnees dans ProgramsData sont conservees)
local function uninstallProgram(id)
  id = sanitizeId(id)
  pcall(fs.delete, fs.combine(PROGRAMS_DIR, id))
  local m = loadManifest()
  m[id] = nil
  saveManifest(m)
  refreshApps()
end


-- ----------------------------------------------------------- ExeliaScript --
-- Les apps de /app/*.as sont ecrites en ExeliaScript : du Lua + une API objet
--   app = exelia.getProgram(app)       display = app.getObject(display)
--   display.window.on()                  window = display.window()
-- Objets : display, keyboard, mouse, timer, storage.  API systeme : exelia.*
local function asColor(c, default)
  if c == nil then return default end
  if type(c) == "string" then return colors[c] or default end
  return c
end

-- Groupes de donnees (.dg) : /AppData/<app>/<nom>.dg
local function dgPath(P, name)
  name = tostring(name)
  if not name:match("^[%w_%-]+$") then
    error("Nom de groupe de donnees invalide : " .. name .. " (lettres, chiffres, _ et - uniquement)", 0)
  end
  return fs.combine(DATA_DIR, P._id, name .. ".dg")
end
local function dgRead(P, name)
  local p = dgPath(P, name)
  if not fs.exists(p) then return nil end
  local t = textutils.unserialize(readFile(p) or "")
  return type(t) == "table" and t or {}
end
local function dgWrite(P, name, t)
  local p = dgPath(P, name)
  local ok, s = pcall(textutils.serialize, t)
  if not ok then error("Valeur non sauvegardable dans un groupe de donnees : " .. tostring(s), 0) end
  pcall(fs.makeDir, DATA_DIR)
  pcall(fs.makeDir, fs.combine(DATA_DIR, P._id))
  if not writeFile(p, s) then error("Ecriture impossible : " .. p, 0) end
end

local function makeDataGroup(P)
  local dg = {}
  dg.create = function(name)                 -- cree le groupe (sans effet s'il existe)
    local t = dgRead(P, name)
    if not t then t = {}; dgWrite(P, name, t) end
    return t
  end
  dg.delete = function(name)                 -- supprime le groupe
    local p = dgPath(P, name)
    P._groups[tostring(name)] = nil
    if fs.exists(p) then fs.delete(p); return true end
    return false
  end
  dg.get = function(name) return dgRead(P, name) end   -- table des variables, ou nil
  dg.registerVariable = function(name, key, getter, setter)
    if type(key) ~= "string" or type(getter) ~= "function" then
      error("registerVariable(nom, variable) : passez une variable, ex. registerVariable(\"scores\", best)", 0)
    end
    name = tostring(name)
    local t = dg.create(name)
    local grp = P._groups[name]
    if not grp then grp = {}; P._groups[name] = grp end
    grp[key] = { get = getter, set = setter }
    local v = t[key]
    if v ~= nil and setter then setter(v) end  -- restaure la valeur sauvegardee
    return v
  end
  dg.save = function(name, key, getter)
    if type(key) ~= "string" or type(getter) ~= "function" then
      error("save(variable, nom) : passez une variable, ex. save(best, \"scores\")", 0)
    end
    local t = dgRead(P, name) or {}
    t[key] = getter()
    dgWrite(P, name, t)
    return true
  end
  dg.saveAll = function(name)                -- sauvegarde toutes les variables enregistrees
    name = tostring(name)
    local t = dgRead(P, name) or {}
    for key, acc in pairs(P._groups[name] or {}) do t[key] = acc.get() end
    dgWrite(P, name, t)
    return true
  end
  return dg
end

local function newProgram(path, id)
  local me = S.curWin
  local P = {
    name = (me and me.title) or id, version = "0.0.0", pastebin = "",
    config = { updating = "manual" },
    _path = path, _id = id, _win = me, _handlers = {}, _timers = {}, _groups = {},
    _quit = false, _windowOn = false,
  }
  -- app.minOsVersion = 3.3 : verifie des l'affectation
  setmetatable(P, { __newindex = function(t, k, v)
    rawset(t, k, v)
    if k == "minOsVersion" and verCmp(VERSION, v) < 0 then
      error("Cette application necessite Exelia OS " .. tostring(v) .. " ou plus recent (version installee : " .. VERSION .. ").", 0)
    end
  end })
  local objs = {}

  local function addHandler(ev, fn)
    if type(fn) ~= "function" then error("Un gestionnaire d'evenement doit etre une fonction.", 3) end
    local l = P._handlers[ev]
    if not l then l = {}; P._handlers[ev] = l end
    l[#l + 1] = fn
  end
  P.on = addHandler
  P.quit = function() P._quit = true end

  local factories = {}

  -- display : la fenetre de l'application ------------------------------------
  factories.display = function()
    local win = {}
    setmetatable(win, {
      __index = function(_, k)
        if k == "width" then return (term.getSize()) end
        if k == "height" then local _, h = term.getSize(); return h end
        if k == "name" then return me and me.title end
      end,
      __newindex = function(t, k, v)
        if k == "name" then
          if me then me.title = tostring(v) end
        else
          rawset(t, k, v)
        end
      end,
    })
    win.clear = function(c)
      term.setBackgroundColor(asColor(c, colors.black)); term.clear(); term.setCursorPos(1, 1)
    end
    win.rect = function(x, y, w, h, c)
      term.setBackgroundColor(asColor(c, colors.black))
      local s = string.rep(" ", math.max(0, w))
      for j = 0, h - 1 do term.setCursorPos(x, y + j); term.write(s) end
    end
    win.pixel = function(x, y, c) win.rect(x, y, 1, 1, c) end
    win.text = function(x, y, s, fg, bg)
      term.setCursorPos(x, y)
      term.setTextColor(asColor(fg, colors.white))
      if bg ~= nil then term.setBackgroundColor(asColor(bg, colors.black)) end
      term.write(tostring(s))
    end
    win.center = function(y, s, fg, bg)
      local w = term.getSize()
      s = tostring(s)
      win.text(math.floor((w - #s) / 2) + 1, y, s, fg, bg)
    end
    win.resize = function(w, h)   -- taille du contenu (sans la barre de titre)
      if not me or me.max then return end
      local nw = math.max(12, math.min(w, X.W))
      local nh = math.max(5, math.min(h + 1, X.H - 1))
      me.w, me.h = nw, nh
      me.x = math.max(1, math.min(me.x, X.W - nw + 1))
      me.y = math.max(2, math.min(me.y, X.H + 1 - nh))
      me.win.reposition(me.x, me.y + 1, nw, nh - 1)
    end
    local wnd = setmetatable({}, { __call = function() return win end })
    wnd.on = function()
      P._windowOn = true
      if me then me.min = false end
      term.setCursorBlink(false)
    end
    wnd.off = function() P._quit = true end
    return { window = wnd }
  end

  -- keyboard ---------------------------------------------------------------
  factories.keyboard = function()
    return {
      onKey = function(fn) addHandler("key", fn) end,       -- fn(nom_touche, maintenue)
      onKeyUp = function(fn) addHandler("keyUp", fn) end,
      onChar = function(fn) addHandler("char", fn) end,     -- fn(caractere)
    }
  end

  -- mouse ------------------------------------------------------------------
  factories.mouse = function()
    return {
      onClick = function(fn) addHandler("mouse_click", fn) end,    -- fn(x, y, bouton)
      onDrag = function(fn) addHandler("mouse_drag", fn) end,
      onRelease = function(fn) addHandler("mouse_up", fn) end,
      onScroll = function(fn) addHandler("mouse_scroll", fn) end,  -- fn(sens, x, y)
    }
  end

  -- timer ------------------------------------------------------------------
  factories.timer = function()
    local function add(sec, fn, rep)
      if type(fn) ~= "function" then error("Le timer attend une fonction.", 3) end
      local h = { fn = fn, sec = sec, rep = rep, id = os.startTimer(sec) }
      P._timers[#P._timers + 1] = h
      return {
        stop = function() h.dead = true end,
        setInterval = function(s) h.sec = s end,
      }
    end
    return {
      every = function(sec, fn) return add(sec, fn, true) end,
      after = function(sec, fn) return add(sec, fn, false) end,
    }
  end

  -- storage : petit stockage cle/valeur (groupe de donnees "storage") ---------
  factories.storage = function()
    return {
      get = function(k, default)
        local t = dgRead(P, "storage") or {}
        local v = t[k]
        if v == nil then return default end
        return v
      end,
      set = function(k, v)
        local t = dgRead(P, "storage") or {}
        t[k] = v
        dgWrite(P, "storage", t)
      end,
    }
  end

  P.getObject = function(t)
    local ty = (type(t) == "table" and t.__type) or tostring(t)
    if objs[ty] then return objs[ty] end
    local f = factories[ty]
    if not f then
      error("Objet inconnu : " .. ty .. " (display, keyboard, mouse, timer, storage)", 2)
    end
    objs[ty] = f()
    return objs[ty]
  end
  return P
end

-- Mise a jour automatique (app.config.updating = "automatic" + app.pastebin)
local function startUpdateCheck(P)
  P._updUrl = nil
  if P.config.updating ~= "automatic" then return end
  local pb = P.pastebin
  if type(pb) ~= "string" or pb == "" or not http then return end
  local url = "https://pastebin.com/raw/" .. pb .. "?cb=" .. stamp()
  if pcall(http.request, url) then P._updUrl = url end
end

local function finishUpdate(P, handle)
  P._updUrl = nil
  local code = handle and handle.readAll()
  if handle then handle.close() end
  if not code or #code < 20 then return end
  local rv = code:match('app%.version%s*=%s*"([^"]+)"')
  if not rv or verCmp(rv, P.version) <= 0 then return end
  local minv = code:match('app%.minOsVersion%s*=%s*"?([%d%.]+)"?')
  if minv and verCmp(VERSION, minv) < 0 then return end
  if not load(preprocess(code), "=update") then return end
  if writeFile(P._path, code) then
    X.msgbox("Mise a jour", tostring(P.name) .. " est passe en version " .. rv .. ". Relancez l'application pour l'utiliser.")
  end
end

local function runProgram(P)
  local function fire(ev, ...)
    local l = P._handlers[ev]
    if l then for _, fn in ipairs({ unpack(l) }) do fn(...) end end
  end
  startUpdateCheck(P)
  fire("start")
  while not P._quit do
    local e, a, b, c, d = os.pullEvent()
    if e == "timer" then
      for _, h in ipairs({ unpack(P._timers) }) do
        if not h.dead and h.id == a then
          h.fn()
          if h.rep and not h.dead then h.id = os.startTimer(h.sec) else h.dead = true end
        end
      end
      local alive = {}
      for _, h in ipairs(P._timers) do if not h.dead then alive[#alive + 1] = h end end
      P._timers = alive
    elseif e == "key" then fire("key", keys.getName(a) or tostring(a), b)
    elseif e == "key_up" then fire("keyUp", keys.getName(a) or tostring(a))
    elseif e == "char" then fire("char", a)
    elseif e == "mouse_click" then fire("mouse_click", b, c, a)
    elseif e == "mouse_drag" then fire("mouse_drag", b, c, a)
    elseif e == "mouse_up" then fire("mouse_up", b, c, a)
    elseif e == "mouse_scroll" then fire("mouse_scroll", a, b, c)
    elseif e == "term_resize" then fire("resize", term.getSize())
    elseif e == "http_success" and a == P._updUrl then finishUpdate(P, b)
    elseif e == "http_failure" and a == P._updUrl then P._updUrl = nil
    else fire(e, a, b, c, d) end
  end
  fire("close")
end



-- liste des applications (integrees + installees) pour exelia.getAppList()
local function scriptAppList()
  local list = {}
  for _, a in ipairs(appList) do
    list[#list + 1] = {
      name = a.name, id = a.id,
      author = a.author or (a.kind == "program" and "inconnu" or "Exelia"),
      description = a.description or "", builtin = (a.kind ~= "program"),
    }
  end
  return list
end

-- API reservee aux applications integrees (System/IntegratedApps) : exelia.system
local function makeSystemApi()
  return {
    storeUrl = STORE_URL,
    httpGet = httpGetText,
    resolveSource = resolveSource,
    sanitizeId = sanitizeId,
    verCmp = verCmp,
    stamp = stamp,
    installProgram = installProgram,
    uninstallProgram = uninstallProgram,
    listPrograms = function()
      local list = {}
      for _, a in ipairs(appList) do
        if a.kind == "program" then
          list[#list + 1] = { id = a.id, name = a.name, author = a.author,
                              description = a.description, w = a.w, h = a.h }
        end
      end
      return list
    end,
    getSource = function(id)
      local m = loadManifest()[id]
      return m and m.source
    end,
    launch = function(id, ...) return X.launchById(id, ...) end,
  }
end

local function makeApi(P, trusted)
  local api = {
    name = "Exelia OS",
    getVersion = function() return VERSION end,
    getUsername = function() return cfg.user or "" end,
    getAppList = scriptAppList,
    notifyUser = function(title, content) X.pushNotif(P.name, title, content) end,
    alertUser = function(text)
      X.msgbox((P._win and P._win.title) or P.name, tostring(text))
    end,
    getProgram = function() return P end,
    dataGroup = makeDataGroup(P),
  }
  if trusted then api.system = makeSystemApi() end
  return api
end

-- Fabrique la fonction qui execute une application ExeliaScript
--   opts.trusted : application integree (acces a exelia.system, Lua complet)
--   opts.inline  : execute dans la fenetre courante (Terminal), sans effacer ni attendre
local function makeAppFn(path, id, opts)
  opts = opts or {}
  return function(...)
    local P = newProgram(path, id)
    if opts.trusted then P.config.waitOnExit = false end
    pcall(fs.makeDir, DATA_DIR)
    pcall(fs.makeDir, fs.combine(DATA_DIR, id))
    local api = makeApi(P, opts.trusted)
    local env
    if opts.trusted then
      env = setmetatable({ fs = userFs }, { __index = _G })
    else
      env = sandboxEnv()
    end
    env.exelia = api
    for _, name in ipairs({ "app", "display", "keyboard", "mouse", "timer", "storage" }) do
      env[name] = setmetatable({ __type = name }, { __tostring = function() return name end })
    end
    if not opts.inline then
      term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
      term.clear(); term.setCursorPos(1, 1)
    end
    local t0 = os.clock()
    local src = readFile(path)
    local fnFile, err
    if src then
      local code = path:match("%.as$") and preprocess(src) or src
      fnFile, err = load(code, "=" .. id, "t", env)
    else
      err = "Fichier introuvable : " .. id
    end
    local ok = fnFile ~= nil
    local looped = false
    if fnFile then
      ok, err = pcall(function(...)
        fnFile(...)
        if P._windowOn or next(P._handlers) ~= nil or #P._timers > 0 then
          looped = true
          runProgram(P)
        end
      end, ...)
      if not ok and tostring(err):find("Terminated") then error("Terminated", 0) end
    end
    if not ok then term.setTextColor(colors.red); print(tostring(err)) end
    if not opts.inline and (not ok or (P.config.waitOnExit ~= false and not looped and os.clock() - t0 < 2)) then
      term.setTextColor(colors.yellow)
      print()
      print(ok and "[Termine - appuyez sur une touche]" or "[Erreur - appuyez sur une touche]")
      os.pullEvent("key")
    end
  end
end

-- ---------------------------------------------- decouverte des applications --
-- Les applications integrees et les programmes decrivent leur apparence dans
-- l'en-tete du fichier : --@name, --@icon, --@color, --@textcolor, --@size, --@author
local function readHeader(path)
  local f = fs.open(path, "r")
  if not f then return {} end
  local meta = {}
  for _ = 1, 25 do
    local line = f.readLine()
    if not line then break end
    local k, v = line:match("^%-%-@(%w+)%s+(.-)%s*$")
    if k then meta[k] = v end
  end
  f.close()
  return meta
end

local function entryFrom(path, id, kind)
  local h = readHeader(path)
  local w, hh = (h.size or ""):match("^(%d+)x(%d+)$")
  local e = {
    id = id, kind = kind, path = path,
    name = h.name or (id:sub(1, 1):upper() .. id:sub(2)),
    author = h.author, description = h.description,
    w = tonumber(w) or 46, h = tonumber(hh) or 15,
  }
  if kind == "integrated" then
    e.icon = h.icon or id:sub(1, 2)
    e.col = h.color and colors[h.color] or colors.lightGray
    e.tc = h.textcolor and colors[h.textcolor] or colors.black
  end
  e.fn = makeAppFn(path, id, { trusted = (kind == "integrated") })
  return e
end

-- Reconstruit la liste des applications, triee par ordre alphabetique
refreshApps = function()
  local list = {}
  for _, a in ipairs(X.fundamental or {}) do list[#list + 1] = a end
  if fs.isDir(INTEGRATED_DIR) then
    for _, f in ipairs(fs.list(INTEGRATED_DIR)) do
      local id = f:match("^(.+)%.as$")
      local p = fs.combine(INTEGRATED_DIR, f)
      if id and not fs.isDir(p) then list[#list + 1] = entryFrom(p, id, "integrated") end
    end
  end
  if fs.isDir(PROGRAMS_DIR) then
    local manifest = loadManifest()
    for _, id in ipairs(fs.list(PROGRAMS_DIR)) do
      local dir = fs.combine(PROGRAMS_DIR, id)
      if fs.isDir(dir) then
        local p = fs.combine(dir, id .. ".as")
        if not fs.exists(p) then p = fs.combine(dir, "main.as") end
        if fs.exists(p) then
          local e = entryFrom(p, id, "program")
          local m = manifest[id]
          if m then
            e.name = m.name or e.name
            e.author = m.author or e.author
            e.description = m.description or e.description
          end
          list[#list + 1] = e
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  for i = #appList, 1, -1 do appList[i] = nil end
  for i, a in ipairs(list) do appList[i] = a end
end

-- ------------------------------------------------------------- exports --
X.paths = {
  CFG_DIR = CFG_DIR, RUN_DIR = RUN_DIR, INTEGRATED_DIR = INTEGRATED_DIR, PROGRAMS_DIR = PROGRAMS_DIR,
  DATA_DIR = DATA_DIR, USER_DIR = USER_DIR, UPDATE_CFG = UPDATE_CFG, BACKUP_DIR = BACKUP_DIR,
  PENDING_FILE = PENDING_FILE, DEFAULT_REPO = DEFAULT_REPO,
}
X.userFs = userFs
X.userPath = vpath
X.readFile, X.writeFile, X.trim, X.stamp, X.verCmp = readFile, writeFile, trim, stamp, verCmp
X.hash, X.loadCfg, X.saveCfg, X.ensureStructure = hash, loadCfg, saveCfg, ensureStructure
X.preprocess, X.sanitizeId, X.httpGetText, X.resolveSource = preprocess, sanitizeId, httpGetText, resolveSource
X.loadManifest, X.saveManifest = loadManifest, saveManifest
X.installProgram, X.uninstallProgram, X.refreshApps = installProgram, uninstallProgram, refreshApps
X.makeAppFn = makeAppFn
