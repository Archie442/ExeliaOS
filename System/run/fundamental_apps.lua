-- ============================================================================
--  Exelia OS - System/run/fundamental_apps.lua
--  Applications fondamentales : Terminal, Explorateur, Parametres,
--  Mise a jour et Infos. (Les autres applications sont dans System/IntegratedApps.)
-- ============================================================================
local X = ...
local fs, S, cfg, appList, wins, unpack = X.fs, X.S, X.cfg, X.appList, X.wins, X.unpack
local VERSION, paths = X.VERSION, X.paths
local ask, wallpapers = X.ask, X.wallpapers
local applyWallpaper, saveCfg, hash, sysReboot, sysShutdown = X.applyWallpaper, X.saveCfg, X.hash, X.sysReboot, X.sysShutdown
local function spawn(...) return X.spawn(...) end
local function msgbox(...) return X.msgbox(...) end

-- ---------------------------------------------------------------- Terminal --
-- Terminal restreint : il ne voit que /User (le reste du systeme n'existe pas).
local function appTerminal()
  local fs = X.userFs
  local cwd = ""
  local history = {}
  local cmds = {}

  local function resolve(p)
    local r = fs.combine(cwd, p or "")
    if r == ".." or r:sub(1, 3) == "../" then return nil end
    return r
  end
  local function say(s, col)
    term.setTextColor(col or colors.white); print(s); term.setTextColor(colors.white)
  end
  local function fail(s) say(s, colors.red) end

  local function wrapNames(entries)
    local w = term.getSize()
    local x = 1
    for _, e in ipairs(entries) do
      local label = e.name .. (e.dir and "/" or "")
      if x > 1 and x + #label > w then print(); x = 1 end
      term.setTextColor(e.col)
      term.write(label .. "  ")
      x = x + #label + 2
    end
    print()
    term.setTextColor(colors.white)
  end

  cmds.help = function()
    say("Commandes : help ls cd pwd cat mkdir rm cp mv echo clear edit run ver whoami time exit", colors.lightGray)
    say("Un fichier .as ou .lua se lance en tapant son nom ou 'run nom'.", colors.lightGray)
  end
  cmds.ls = function(a)
    local p = resolve(a[1])
    if not p or not fs.isDir(p) then return fail("Dossier introuvable.") end
    local list = fs.list(p)
    table.sort(list, function(x, y) return x:lower() < y:lower() end)
    local entries = {}
    for _, n in ipairs(list) do
      local d = fs.isDir(fs.combine(p, n))
      local col = d and colors.yellow or (n:match("%.as$") and colors.cyan or colors.white)
      entries[#entries + 1] = { name = n, dir = d, col = col }
    end
    wrapNames(entries)
  end
  cmds.cd = function(a)
    local p = resolve(a[1] or "")
    if p and fs.isDir(p) then cwd = p else fail("Dossier introuvable.") end
  end
  cmds.pwd = function() say("/" .. cwd) end
  cmds.cat = function(a)
    local p = a[1] and resolve(a[1])
    if not p or not fs.exists(p) or fs.isDir(p) then return fail("Fichier introuvable.") end
    local f = fs.open(p, "r")
    if f then print(f.readAll()); f.close() end
  end
  cmds.mkdir = function(a)
    local p = a[1] and resolve(a[1])
    if not p then return fail("Usage : mkdir <dossier>") end
    if not pcall(fs.makeDir, p) then fail("Creation impossible.") end
  end
  cmds.rm = function(a)
    local p = a[1] and resolve(a[1])
    if not p or p == "" or not fs.exists(p) then return fail("Introuvable.") end
    if not pcall(fs.delete, p) then fail("Suppression impossible.") end
  end
  cmds.cp = function(a)
    local s, d = a[1] and resolve(a[1]), a[2] and resolve(a[2])
    if not s or not d or not fs.exists(s) then return fail("Usage : cp <source> <destination>") end
    if not pcall(fs.copy, s, d) then fail("Copie impossible.") end
  end
  cmds.mv = function(a)
    local s, d = a[1] and resolve(a[1]), a[2] and resolve(a[2])
    if not s or not d or not fs.exists(s) then return fail("Usage : mv <source> <destination>") end
    if not pcall(fs.move, s, d) then fail("Deplacement impossible.") end
  end
  cmds.echo = function(a) print(table.concat(a, " ")) end
  cmds.clear = function() term.clear(); term.setCursorPos(1, 1) end
  cmds.edit = function(a)
    local p = a[1] and resolve(a[1])
    if not p then return fail("Usage : edit <fichier>") end
    X.launchById("editor", p)
  end
  cmds.ver = function() say(X.NAME .. " " .. VERSION, colors.lime) end
  cmds.whoami = function() print(cfg.user or "") end
  cmds.time = function() print(textutils.formatTime(os.time(), cfg.clock24)) end

  local function runFile(a)
    local p = a[1] and resolve(a[1])
    if p and fs.isDir(p) then p = nil end
    if p and not fs.exists(p) then
      if fs.exists(p .. ".as") then p = p .. ".as" elseif fs.exists(p .. ".lua") then p = p .. ".lua" else p = nil end
    end
    if not p then return fail("Programme introuvable.") end
    local id = X.sanitizeId(fs.getName(p):gsub("%.%w+$", ""))
    local args = {}
    for i = 2, #a do args[#args + 1] = a[i] end
    local ok, err = pcall(X.makeAppFn(X.userPath(p), id, { trusted = false, inline = true }), unpack(args))
    if not ok then
      if tostring(err):find("Terminated") then error("Terminated", 0) end
      fail(tostring(err))
    end
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
  end
  cmds.run = runFile

  local function complete(text)
    local word = text:match("([^%s]*)$") or ""
    local ok, list = pcall(fs.complete, word, cwd, true, true)
    return ok and list or {}
  end

  term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
  term.clear(); term.setCursorPos(1, 1)
  say(X.NAME .. " Terminal - tapez 'help'", colors.lime)
  while true do
    term.setTextColor(colors.yellow)
    write("/" .. cwd .. "> ")
    term.setTextColor(colors.white)
    local line = read(nil, history, complete)
    local a = {}
    for w in line:gmatch("%S+") do a[#a + 1] = w end
    if #a > 0 then
      history[#history + 1] = line
      local name = table.remove(a, 1)
      if name == "exit" then return end
      if cmds[name] then
        local ok, err = pcall(cmds[name], a)
        if not ok then
          if tostring(err):find("Terminated") then error("Terminated", 0) end
          fail(tostring(err))
        end
      else
        table.insert(a, 1, name)
        runFile(a)
      end
    end
  end
end

-- --------------------------------------------------------------- Explorateur --
local function appExplorer(start)
  local fs = X.userFs
  local dir = fs.combine("", start or "")
  local hist, fwd = {}, {}
  local view = "list"              -- "list" ou "grid"
  local sel, top = 1, 0
  local all, items = {}, {}
  local filter = ""
  local clip = nil                 -- { path, name }
  local msg, msgCol = "", colors.gray
  local lastClick, lastIdx = 0, 0
  local ctx = nil                  -- menu contextuel
  local hits = { btns = {} }
  local render

  -- ------------------------------------------------------------- outils --
  local function tr(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
  local function say(m, c) msg, msgCol = m, c or colors.gray end
  local function fpath(name) return fs.combine(dir, name) end
  local function ext(it) return (it.name:match("%.(%w+)$") or ""):lower() end

  local function fmtSize(n)
    if n < 1024 then return n .. " o" end
    if n < 1048576 then return string.format("%.1f Ko", n / 1024) end
    return string.format("%.1f Mo", n / 1048576)
  end
  local function fmtDate(path)
    local ok, a = pcall(fs.attributes, path)
    if ok and type(a) == "table" and a.modified and a.modified > 0 then
      local ok2, s = pcall(os.date, "%d/%m %H:%M", math.floor(a.modified / 1000))
      if ok2 and s then return s end
    end
    return ""
  end
  local function iconCol(it)
    if it.d then return colors.yellow end
    local e = ext(it)
    if e == "lua" then return colors.lime end
    if e == "as" then return colors.cyan end
    if e == "dg" then return colors.lightBlue end
    if e == "txt" or e == "md" or e == "json" or e == "cfg" or e == "log" then return colors.lightBlue end
    if e == "nfp" or e == "nft" or e == "bimg" then return colors.orange end
    return colors.lightGray
  end
  local function kindName(it)
    if it.d then return "Dossier" end
    local e = ext(it)
    if e == "lua" then return "Programme Lua" end
    if e == "as" then return "Application ExeliaScript" end
    if e == "dg" then return "Groupe de donnees" end
    if e == "txt" or e == "md" or e == "log" then return "Texte" end
    if e == "json" or e == "cfg" then return "Configuration" end
    return "Fichier"
  end

  local function applyFilter()
    items = {}
    local q = filter:lower()
    for _, it in ipairs(all) do
      if q == "" or it.name:lower():find(q, 1, true) then items[#items + 1] = it end
    end
    if sel > #items then sel = #items end
    if sel < 1 then sel = 1 end
  end

  local function refresh()
    all = {}
    local ok, l = pcall(fs.list, dir)
    if not ok then l = {} end
    table.sort(l, function(a, b)
      local da, db = fs.isDir(fs.combine(dir, a)), fs.isDir(fs.combine(dir, b))
      if da ~= db then return da end
      return a:lower() < b:lower()
    end)
    for _, n in ipairs(l) do
      local p = fs.combine(dir, n)
      local d = fs.isDir(p)
      local sz = 0
      if not d then
        local ok2, v = pcall(fs.getSize, p)
        sz = ok2 and v or 0
      end
      all[#all + 1] = { name = n, d = d, size = sz, path = p }
    end
    applyFilter()
  end

  local function selectName(n)
    for i, it in ipairs(items) do if it.name == n then sel = i end end
  end

  -- --------------------------------------------------------- navigation --
  local function go(newDir, noHist)
    newDir = fs.combine("", newDir)
    if not fs.isDir(newDir) then say("Dossier introuvable.", colors.red) return end
    if not noHist then hist[#hist + 1] = dir; fwd = {} end
    dir = newDir; sel = 1; top = 0; filter = ""; ctx = nil
    refresh()
  end
  local function back()
    if #hist > 0 then fwd[#fwd + 1] = dir; go(table.remove(hist), true) end
  end
  local function forward()
    if #fwd > 0 then hist[#hist + 1] = dir; go(table.remove(fwd), true) end
  end
  local function up() if dir ~= "" then go(fs.getDir(dir)) end end
  local function cur() return items[sel] end

  local function openItem(it)
    if not it then return end
    if it.d then go(it.path)
    else X.launchById("editor", it.path) end
  end
  local function runItem(it)
    if it and not it.d then
      local id = X.sanitizeId(it.name:gsub("%.%w+$", ""))
      spawn(it.name, X.makeAppFn(X.userPath(it.path), id, { trusted = false }), 46, 15)
    end
  end

  -- ------------------------------------------------------ boites modales --
  local function box(w2, h2, title)
    local w, h = term.getSize()
    local x, y = math.floor((w - w2) / 2) + 1, math.max(1, math.floor((h - h2) / 2))
    term.setBackgroundColor(colors.gray)   -- ombre
    for j = 0, h2 - 1 do term.setCursorPos(x + 1, y + j + 1); term.write(string.rep(" ", w2)) end
    term.setBackgroundColor(colors.white)
    for j = 0, h2 - 1 do term.setCursorPos(x, y + j); term.write(string.rep(" ", w2)) end
    term.setBackgroundColor(colors.lightGray); term.setCursorPos(x, y); term.write(string.rep(" ", w2))
    term.setCursorPos(x + 1, y); term.setBackgroundColor(colors.red); term.write(" ")
    term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
    term.setCursorPos(x + math.floor((w2 - #title) / 2), y); term.write(title)
    return x, y
  end

  local function confirm(title, text, okLabel)
    render()
    while true do
      local tw = term.getSize()
      local w2 = math.min(38, tw - 2)
      local x, y = box(w2, 7, title)
      term.setBackgroundColor(colors.white); term.setTextColor(colors.black)
      term.setCursorPos(x + 2, y + 2); term.write(text:sub(1, w2 - 4))
      term.setTextColor(colors.gray)
      term.setCursorPos(x + 2, y + 3); term.write(text:sub(w2 - 3, 2 * (w2 - 4)))
      local b1, b2 = " Annuler ", " " .. okLabel .. " "
      local bx2 = x + w2 - #b2 - 2
      local bx1 = bx2 - #b1 - 1
      term.setCursorPos(bx1, y + 5); term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black); term.write(b1)
      term.setCursorPos(bx2, y + 5); term.setBackgroundColor(colors.red); term.setTextColor(colors.white); term.write(b2)
      local e, a, b, c = os.pullEvent()
      if e == "mouse_click" and c == y + 5 then
        if b >= bx2 and b < bx2 + #b2 then return true end
        if b >= bx1 and b < bx1 + #b1 then return false end
      elseif e == "key" then
        if a == keys.enter then return true end
        if a == keys.backspace then return false end
      elseif e == "char" then
        if a == "o" or a == "y" then return true end
        if a == "n" then return false end
      end
    end
  end

  local function promptBox(title, label, default)
    render()
    local tw = term.getSize()
    local w2 = math.min(38, tw - 2)
    local x, y = box(w2, 8, title)
    term.setBackgroundColor(colors.white); term.setTextColor(colors.gray)
    term.setCursorPos(x + 2, y + 2); term.write(label:sub(1, w2 - 4))
    term.setCursorPos(x + 2, y + 6); term.write(("Entree = valider (vide = annuler)"):sub(1, w2 - 4))
    term.setBackgroundColor(colors.lightGray)
    term.setCursorPos(x + 2, y + 4); term.write(string.rep(" ", w2 - 4))
    term.setCursorPos(x + 2, y + 4); term.setTextColor(colors.black)
    term.setCursorBlink(true)
    local r = read(nil, nil, nil, default)
    term.setCursorBlink(false)
    return tr(r or "")
  end

  -- ------------------------------------------------------------ actions --
  local function doNewFile()
    local n = promptBox("Nouveau fichier", "Nom du fichier :", "")
    if n == "" then return end
    local p = fpath(n)
    if fs.exists(p) then say("Ce nom existe deja.", colors.red) return end
    local ok = pcall(function() local f = fs.open(p, "w"); f.close() end)
    refresh(); selectName(n)
    if ok then say("Fichier cree.", colors.green); openItem({ name = n, d = false, path = p })
    else say("Creation impossible.", colors.red) end
  end
  local function doNewFolder()
    local n = promptBox("Nouveau dossier", "Nom du dossier :", "")
    if n == "" then return end
    if fs.exists(fpath(n)) then say("Ce nom existe deja.", colors.red) return end
    if pcall(fs.makeDir, fpath(n)) then say("Dossier cree.", colors.green) else say("Creation impossible.", colors.red) end
    refresh(); selectName(n)
  end
  local function doRename()
    local it = cur()
    if not it then return end
    local n = promptBox("Renommer", "Nouveau nom pour " .. it.name .. " :", it.name)
    if n == "" or n == it.name then return end
    if fs.exists(fpath(n)) then say("Ce nom existe deja.", colors.red) return end
    if pcall(fs.move, it.path, fpath(n)) then say("Renomme.", colors.green) else say("Renommage impossible.", colors.red) end
    refresh(); selectName(n)
  end
  local function doDelete()
    local it = cur()
    if not it then return end
    local okRO, ro = pcall(fs.isReadOnly, it.path)
    if okRO and ro then say("Element en lecture seule.", colors.red) return end
    if confirm("Supprimer", "Supprimer \"" .. it.name .. "\" ? Cette action est irreversible.", "Supprimer") then
      if pcall(fs.delete, it.path) then say("Supprime.", colors.green) else say("Suppression impossible.", colors.red) end
      refresh()
    end
  end
  local function doCopy()
    local it = cur()
    if not it then return end
    clip = { path = it.path, name = it.name }
    say("Copie : " .. it.name, colors.blue)
  end
  local function doPaste()
    if not clip then say("Presse-papiers vide.", colors.gray) return end
    if not fs.exists(clip.path) then say("L'element copie n'existe plus.", colors.red) return end
    local base, ex = clip.name:match("^(.-)(%.[^%.]*)$")
    if not base or base == "" then base, ex = clip.name, "" end
    local n = clip.name
    local i = 0
    while fs.exists(fpath(n)) do
      i = i + 1
      n = base .. "_copie" .. (i > 1 and i or "") .. ex
    end
    if pcall(fs.copy, clip.path, fpath(n)) then say("Colle : " .. n, colors.green) else say("Copie impossible.", colors.red) end
    refresh(); selectName(n)
  end

  -- ------------------------------------------------------------- rendu --
  local function sideItems()
    local list = {}
    list[#list + 1] = { label = "Utilisateur", path = "", col = colors.blue }
    if fs.exists("Documents") then list[#list + 1] = { label = "Documents", path = "Documents", col = colors.orange } end
    if fs.exists("Desktop") then list[#list + 1] = { label = "Bureau", path = "Desktop", col = colors.green } end
    return list
  end

  local function geo()
    local w, h = term.getSize()
    local sw = (w >= 40) and 13 or 0
    local g = { w = w, h = h, sw = sw, cw = w - sw - 1 }
    if view == "list" then
      g.R = math.max(1, h - 4)
    else
      g.cols = math.max(1, math.floor(g.cw / 12))
      g.R = math.max(1, math.floor((h - 3) / 4))
    end
    return g
  end

  local function totalRows(g)
    if view == "list" then return #items end
    return math.ceil(#items / g.cols)
  end
  local function ensureVisible(g)
    local row = (view == "list") and (sel - 1) or math.floor((sel - 1) / g.cols)
    if row < top then top = row end
    if row >= top + g.R then top = row - g.R + 1 end
    top = math.max(0, math.min(top, math.max(0, totalRows(g) - g.R)))
  end

  render = function()
    local g = geo()
    ensureVisible(g)
    local w, h, sw = g.w, g.h, g.sw
    hits = { btns = {} }
    local function put(x, y, s, fg, bg)
      term.setCursorPos(x, y); term.setTextColor(fg); term.setBackgroundColor(bg); term.write(s)
    end
    local function fill(x, y, n, bg) put(x, y, string.rep(" ", math.max(0, n)), colors.black, bg) end
    local function button(x, y, s, fg, bg, fn)
      put(x, y, s, fg, bg)
      hits.btns[#hits.btns + 1] = { x, x + #s - 1, y, fn }
    end
    term.setCursorBlink(false)
    term.setBackgroundColor(colors.white); term.clear()

    -- barre d'outils (2 lignes)
    fill(1, 1, w, colors.lightGray); fill(1, 2, w, colors.lightGray)
    button(2, 1, " < ", #hist > 0 and colors.black or colors.gray, colors.white, back)
    button(6, 1, " > ", #fwd > 0 and colors.black or colors.gray, colors.white, forward)
    button(10, 1, " ^ ", dir ~= "" and colors.black or colors.gray, colors.white, up)
    local gridX, listX = w - 3, w - 7
    button(listX, 1, " = ", view == "list" and colors.white or colors.black, view == "list" and colors.blue or colors.white,
      function() view = "list"; top = 0 end)
    button(gridX, 1, " # ", view == "grid" and colors.white or colors.black, view == "grid" and colors.blue or colors.white,
      function() view = "grid"; top = 0 end)
    local bcEnd = listX - 2
    if w >= 46 then
      local sx = listX - 15
      fill(sx, 1, 14, colors.white)
      if filter == "" then put(sx + 1, 1, "Filtrer...", colors.gray, colors.white)
      else put(sx + 1, 1, filter:sub(-12), colors.black, colors.white) end
      hits.btns[#hits.btns + 1] = { sx, sx + 13, 1, function() filter = ""; applyFilter() end }
      bcEnd = sx - 2
    end
    local bw = bcEnd - 14 + 1
    if bw > 4 then
      fill(14, 1, bw, colors.white)
      local s = "/" .. dir
      if #s > bw - 2 then s = ".." .. s:sub(-(bw - 4)) end
      put(15, 1, s, colors.black, colors.white)
    end
    local acts = {
      { " +Fichier ", colors.black, doNewFile }, { " +Dossier ", colors.black, doNewFolder },
      { " Copier ", colors.black, doCopy }, { " Coller ", clip and colors.black or colors.gray, doPaste },
      { " Suppr ", colors.red, doDelete },
    }
    local ax = 2
    for _, d in ipairs(acts) do
      if ax + #d[1] - 1 <= w then button(ax, 2, d[1], d[2], colors.white, d[3]) end
      ax = ax + #d[1] + 1
    end

    -- panneau lateral
    if sw > 0 then
      for y = 3, h - 1 do fill(1, y, sw, colors.lightGray) end
      put(2, 3, "FAVORIS", colors.gray, colors.lightGray)
      local y = 4
      for _, en in ipairs(sideItems()) do
        if y > h - 1 then break end
        if en.header then
          y = y + 1
          put(2, y, en.header:sub(1, sw - 2), colors.gray, colors.lightGray)
          y = y + 1
        else
          local active = (dir == en.path) or (en.path ~= "" and dir:sub(1, #en.path + 1) == en.path .. "/")
          local bg = active and colors.blue or colors.lightGray
          fill(1, y, sw, bg)
          put(2, y, " ", colors.black, en.col)
          put(4, y, en.label:sub(1, sw - 4), active and colors.white or colors.black, bg)
          hits.btns[#hits.btns + 1] = { 1, sw, y, function() go(en.path) end }
          y = y + 1
        end
      end
    end

    -- contenu
    local x0 = sw + 1
    if view == "list" then
      local showDate = g.cw >= 36
      local dateW = showDate and 12 or 0
      local sizeW = 9
      local sizeX = x0 + g.cw - dateW - sizeW
      local dateX = x0 + g.cw - dateW
      put(x0 + 1, 3, "Nom", colors.gray, colors.white)
      put(sizeX + sizeW - 6, 3, "Taille", colors.gray, colors.white)
      if showDate then put(dateX + 1, 3, "Modifie", colors.gray, colors.white) end
      for r = 0, g.R - 1 do
        local idx = top + r + 1
        local it = items[idx]
        if not it then break end
        local y = 4 + r
        local isSel = (idx == sel)
        local bg = isSel and colors.blue or colors.white
        fill(x0, y, g.cw, bg)
        put(x0 + 1, y, "  ", colors.black, iconCol(it))
        local nfg = isSel and colors.white or (it.name:sub(1, 1) == "." and colors.gray or colors.black)
        put(x0 + 4, y, it.name:sub(1, math.max(1, sizeX - x0 - 5)), nfg, bg)
        local s = it.d and "--" or fmtSize(it.size)
        put(sizeX + sizeW - #s, y, s, isSel and colors.white or colors.gray, bg)
        if showDate then
          it.date = it.date or fmtDate(it.path)
          put(dateX + 1, y, it.date, isSel and colors.white or colors.gray, bg)
        end
      end
      if #items == 0 then
        put(x0 + 2, 5, filter ~= "" and "Aucun resultat" or "Dossier vide", colors.gray, colors.white)
      end
      if #items > g.R then
        local thumb = math.max(1, math.floor(g.R * g.R / #items))
        local tt = math.floor(top * (g.R - thumb) / math.max(1, #items - g.R))
        for r = 0, g.R - 1 do
          put(w, 4 + r, " ", colors.black, (r >= tt and r < tt + thumb) and colors.gray or colors.white)
        end
      end
    else
      for r = 0, g.R - 1 do
        for c = 0, g.cols - 1 do
          local idx = (top + r) * g.cols + c + 1
          local it = items[idx]
          if it then
            local cx, cy = x0 + c * 12, 3 + r * 4
            local isSel = (idx == sel)
            local col = iconCol(it)
            if isSel then
              put(cx + 2, cy, "        ", colors.black, colors.lightGray)
              put(cx + 2, cy + 1, "        ", colors.black, colors.lightGray)
            end
            if it.d then
              put(cx + 3, cy, "   ", colors.black, colors.orange)
              put(cx + 6, cy, "   ", colors.black, col)
              put(cx + 3, cy + 1, "      ", colors.black, col)
            else
              put(cx + 3, cy, "      ", colors.black, col)
              put(cx + 3, cy + 1, "      ", colors.black, col)
              local gl = ext(it):sub(1, 4):upper()
              if gl ~= "" then put(cx + 3 + math.floor((6 - #gl) / 2), cy + 1, gl, colors.black, col) end
            end
            local nm = it.name:sub(1, 11)
            put(cx + math.floor((12 - #nm) / 2), cy + 2, nm,
              isSel and colors.white or colors.black, isSel and colors.blue or colors.white)
          end
        end
      end
      if #items == 0 then
        put(x0 + 2, 5, filter ~= "" and "Aucun resultat" or "Dossier vide", colors.gray, colors.white)
      end
    end

    -- barre d'etat
    fill(1, h, w, colors.lightGray)
    if msg ~= "" then
      put(2, h, msg:sub(1, w - 2), msgCol, colors.lightGray)
    else
      local it = items[sel]
      local s = #items .. " element(s)"
      if filter ~= "" then s = s .. "  filtre : " .. filter end
      if it then s = s .. "  |  " .. it.name .. (it.d and " (dossier)" or ("  " .. kindName(it) .. "  " .. fmtSize(it.size))) end
      local okF, free = pcall(fs.getFreeSpace, dir == "" and "/" or dir)
      local fs2 = okF and free and (fmtSize(free) .. " libres") or ""
      put(2, h, s:sub(1, math.max(1, w - #fs2 - 3)), colors.gray, colors.lightGray)
      put(w - #fs2, h, fs2, colors.gray, colors.lightGray)
    end

    -- menu contextuel
    if ctx then
      local mw = 0
      for _, m in ipairs(ctx.items) do mw = math.max(mw, #m[1] + 2) end
      ctx.mw = mw
      ctx.x = math.max(1, math.min(ctx.x, w - mw))
      ctx.y = math.max(1, math.min(ctx.y, h - #ctx.items))
      for j = 1, #ctx.items do put(ctx.x + 1, ctx.y + j, string.rep(" ", mw), colors.black, colors.gray) end
      for j, m in ipairs(ctx.items) do
        put(ctx.x, ctx.y + j - 1, (" " .. m[1] .. string.rep(" ", mw)):sub(1, mw),
          m[3] or colors.black, colors.white)
      end
    end
  end

  -- ---------------------------------------------------------- evenements --
  local function itemAt(x, y, g)
    local x0 = g.sw + 1
    if x < x0 or x >= x0 + g.cw then return nil end
    if view == "list" then
      if y >= 4 and y < 4 + g.R then
        local idx = top + (y - 4) + 1
        if items[idx] then return idx end
      end
    elseif y >= 3 then
      local c, r = math.floor((x - x0) / 12), math.floor((y - 3) / 4)
      if c < g.cols and r < g.R then
        local idx = (top + r) * g.cols + c + 1
        if items[idx] then return idx end
      end
    end
    return nil
  end

  local function openContext(x, y, onItem)
    local m = {}
    if onItem then
      local it = cur()
      m[#m + 1] = { "Ouvrir", function() openItem(cur()) end }
      if it and not it.d and (ext(it) == "lua" or ext(it) == "as") then m[#m + 1] = { "Executer", function() runItem(cur()) end } end
      m[#m + 1] = { "Renommer", doRename }
      m[#m + 1] = { "Copier", doCopy }
      m[#m + 1] = { "Supprimer", doDelete, colors.red }
    else
      m[#m + 1] = { "Nouveau fichier", doNewFile }
      m[#m + 1] = { "Nouveau dossier", doNewFolder }
      m[#m + 1] = { "Coller", doPaste, clip and colors.black or colors.gray }
    end
    ctx = { x = x, y = y, items = m }
  end

  refresh()
  while true do
    render()
    local e, a, b, c = os.pullEvent()
    local g = geo()
    if e == "char" then
      filter = filter .. a; sel = 1; top = 0; ctx = nil; msg = ""
      applyFilter()
    elseif e == "key" then
      msg = ""; ctx = nil
      local step = 1
      if a == keys.up then sel = sel - ((view == "grid") and g.cols or 1)
      elseif a == keys.down then sel = sel + ((view == "grid") and g.cols or 1)
      elseif a == keys.left and view == "grid" then sel = sel - 1
      elseif a == keys.right and view == "grid" then sel = sel + 1
      elseif a == keys.pageUp then sel = sel - g.R
      elseif a == keys.pageDown then sel = sel + g.R
      elseif a == keys.home then sel = 1
      elseif a == keys["end"] then sel = #items
      elseif a == keys.enter then openItem(cur())
      elseif a == keys.backspace then
        if filter ~= "" then filter = filter:sub(1, -2); applyFilter() else up() end
      elseif a == keys.delete then doDelete()
      elseif a == keys.f2 then doRename()
      elseif a == keys.f5 then refresh() end
      sel = math.max(1, math.min(#items, sel))
    elseif e == "mouse_scroll" then
      ctx = nil
      top = math.max(0, math.min(math.max(0, totalRows(g) - g.R), top + a))
      if view == "list" then sel = math.max(top + 1, math.min(sel, top + g.R))
      else
        local row = math.floor((sel - 1) / g.cols)
        row = math.max(top, math.min(row, top + g.R - 1))
        sel = math.min(#items, row * g.cols + ((sel - 1) % g.cols) + 1)
      end
      sel = math.max(1, math.min(#items, sel))
    elseif e == "mouse_click" then
      msg = ""
      local handled = false
      if ctx then
        if b >= ctx.x and b < ctx.x + (ctx.mw or 0) and c >= ctx.y and c < ctx.y + #ctx.items then
          local m = ctx.items[c - ctx.y + 1]
          ctx = nil
          if m then m[2]() end
        else
          ctx = nil
        end
        handled = true
      end
      if not handled and a == 1 then
        for _, bt in ipairs(hits.btns) do
          if c == bt[3] and b >= bt[1] and b <= bt[2] then bt[4](); handled = true; break end
        end
      end
      if not handled then
        local idx = itemAt(b, c, g)
        if a == 2 then
          if idx then sel = idx; openContext(b, c, true)
          elseif b > g.sw and c >= 3 and c < g.h then openContext(b, c, false) end
        elseif idx then
          if idx == sel and idx == lastIdx and os.clock() - lastClick < 0.7 then openItem(items[idx])
          else sel = idx end
          lastIdx, lastClick = idx, os.clock()
        end
      end
    end
  end
end


-- ---------------------------------------------------------------- Parametres --
local function changePass()
  if cfg.pass ~= "" then
    local o = ask("Ancien mdp:", nil, "*")
    if hash(o) ~= cfg.pass then msgbox("Parametres", "Mot de passe incorrect."); return end
  end
  local n1 = ask("Nouveau mdp:", nil, "*")
  local n2 = ask("Confirmer:", nil, "*")
  if n1 ~= n2 then msgbox("Parametres", "Les mots de passe different."); return end
  cfg.pass = (n1 == "") and "" or hash(n1)
  saveCfg()
  msgbox("Parametres", "Mot de passe mis a jour.")
end

local function appSettings()
  while true do
    local w = term.getSize()
    local btns = {}
    local function label(x, y, s, fg)
      term.setCursorPos(x, y); term.setBackgroundColor(colors.white)
      term.setTextColor(fg or colors.black); term.write(s)
    end
    local function btn(x, y, s, bg, fn, fg)
      term.setCursorPos(x, y); term.setBackgroundColor(bg)
      term.setTextColor(fg or colors.white); term.write(s)
      btns[#btns + 1] = { x, y, x + #s - 1, fn }
    end
    term.setBackgroundColor(colors.white); term.setTextColor(colors.black); term.clear()
    label(2, 1, "PARAMETRES", colors.gray)
    label(2, 3, "Fond d'ecran")
    local x, y = 2, 4
    for i, wp in ipairs(wallpapers) do
      local s = " " .. wp.name .. " "
      if x + #s > w then x = 2; y = y + 1 end
      btn(x, y, s, cfg.wall == i and colors.blue or colors.gray,
        function() cfg.wall = i; applyWallpaper(i); saveCfg() end)
      x = x + #s + 1
    end
    label(2, 7, "Horloge")
    btn(12, 7, cfg.clock24 and " 24 h " or " 12 h ", colors.blue,
      function() cfg.clock24 = not cfg.clock24; saveCfg() end)
    label(2, 9, "Nom du PC : " .. (os.getComputerLabel() or "(aucun)"))
    btn(2, 10, " Modifier ", colors.blue, function()
      local n = ask("Nom du PC:", os.getComputerLabel() or "")
      if n ~= "" then os.setComputerLabel(n) end
    end)
    label(2, 11, "Utilisateur : " .. tostring(cfg.user))
    btn(2, 12, " Renommer ", colors.blue, function()
      local n = ask("Nouveau nom:", cfg.user or "")
      if n ~= "" then cfg.user = n; saveCfg() end
    end)
    btn(14, 12, " Mot de passe ", colors.blue, changePass)
    btn(2, 13, " Mise a jour ", colors.green, function() X.launchById("update") end)
    btn(16, 13, " Redemarrer ", colors.red, sysReboot)
    local e, a, b, c = os.pullEvent()
    if e == "mouse_click" then
      for _, bt in ipairs(btns) do
        if c == bt[2] and b >= bt[1] and b <= bt[3] then bt[4]() break end
      end
    end
  end
end


-- ----------------------------------------------------------- Infos systeme --
local function appInfo()
  while true do
    local w = term.getSize()
    term.setBackgroundColor(colors.white); term.setTextColor(colors.black); term.clear()
    local kind = "Ordinateur"
    if pocket then kind = "Pocket" elseif turtle then kind = "Tortue" end
    local free = fs.getFreeSpace("/")
    local okc, cap = pcall(fs.getCapacity, "/")
    local per = peripheral.getNames()
    local rows = {
      { "Exelia OS " .. VERSION, colors.blue },
      { "" },
      { "Systeme  : " .. os.version() },
      { "Hote     : " .. tostring(_HOST or "?") },
      { "Type     : " .. kind },
      { "ID / nom : " .. os.getComputerID() .. " / " .. (os.getComputerLabel() or "-") },
      { "Utilisat.: " .. tostring(cfg.user) },
      { "Uptime   : " .. math.floor(os.clock()) .. " s" },
      { "Heure MC : " .. textutils.formatTime(os.time(), true) .. " (jour " .. os.day() .. ")" },
      { "Disque   : " .. math.floor(free / 1024) .. " Ko libres" ..
        ((okc and cap) and (" / " .. math.floor(cap / 1024) .. " Ko") or "") },
      { "Fenetres : " .. #wins },
      { "Peripheriques (" .. #per .. ") : " .. table.concat(per, ", ") },
    }
    for i, r in ipairs(rows) do
      term.setCursorPos(2, i); term.setTextColor(r[2] or colors.black)
      term.write(r[1]:sub(1, w - 2))
    end
    local tm = os.startTimer(1)
    repeat
      local ev = { os.pullEvent() }
    until (ev[1] == "timer" and ev[2] == tm) or ev[1] == "term_resize"
  end
end


-- ------------------------------------------------------------ Mise a jour --
-- Mise a jour du systeme depuis le depot GitHub indique dans System/config/update.cfg.
-- Le depot contient un manifest.json : { "version": "4.1", "files": [ "startup.lua", ... ] }
local function readRepo()
  local d = fs.exists(paths.UPDATE_CFG) and X.readFile(paths.UPDATE_CFG) or nil
  local t = d and textutils.unserialize(d)
  local repo = (type(t) == "table" and type(t.repo) == "string" and t.repo) or paths.DEFAULT_REPO
  if repo:sub(-1) ~= "/" then repo = repo .. "/" end
  return repo
end

-- seuls le lanceur et les composants du systeme peuvent etre mis a jour
local function validPath(p)
  if type(p) ~= "string" or p:find("%.%.") or p:find("^/") or p:find("\\") then return false end
  return p == "startup.lua" or p:match("^System/run/[%w_%-]+%.lua$") ~= nil
      or p:match("^System/IntegratedApps/[%w_%-]+%.as$") ~= nil
end

local function writeDeep(path, data)
  pcall(fs.makeDir, fs.getDir(path))
  return X.writeFile(path, data)
end

local function walk(dir, fn, rel)
  rel = rel or ""
  for _, name in ipairs(fs.list(fs.combine(dir, rel))) do
    local r = fs.combine(rel, name)
    if fs.isDir(fs.combine(dir, r)) then walk(dir, fn, r) else fn(r) end
  end
end

-- Telecharge et verifie toutes les fichiers de la version distante
local function fetchRelease(progress)
  local base = readRepo()
  progress(0.05, "Lecture du manifeste...")
  local body, err = X.httpGetText(base .. "manifest.json?cb=" .. X.stamp())
  if not body then return nil, err end
  local man = textutils.unserializeJSON(body)
  if type(man) ~= "table" or type(man.version) ~= "string" or type(man.files) ~= "table" then
    return nil, "Manifeste invalide."
  end
  local files, n = {}, #man.files
  for i, path in ipairs(man.files) do
    if not validPath(path) then return nil, "Fichier refuse : " .. tostring(path) end
    progress(0.1 + 0.6 * (i - 1) / math.max(1, n), path)
    local code, e = X.httpGetText(base .. path .. "?cb=" .. X.stamp())
    if not code then return nil, e end
    local compiled, serr
    if path:match("%.as$") then compiled, serr = load(X.preprocess(code), "=" .. path)
    else compiled, serr = load(code, "=" .. path) end
    if not compiled then return nil, "Erreur dans " .. path .. " : " .. tostring(serr) end
    files[#files + 1] = { path = path, code = code }
  end
  return { version = man.version, files = files }
end

local function installRelease(rel)
  pcall(fs.delete, paths.BACKUP_DIR)
  pcall(fs.makeDir, paths.BACKUP_DIR)
  for _, f in ipairs(rel.files) do
    local old = fs.exists(f.path) and X.readFile(f.path) or nil
    if old then writeDeep(fs.combine(paths.BACKUP_DIR, f.path), old) end
  end
  X.writeFile(paths.PENDING_FILE, rel.version)   -- le lanceur restaure si le demarrage echoue
  local function rollback()
    walk(paths.BACKUP_DIR, function(r)
      local d = X.readFile(fs.combine(paths.BACKUP_DIR, r))
      if d then writeDeep(r, d) end
    end)
    pcall(fs.delete, paths.PENDING_FILE)
  end
  for _, f in ipairs(rel.files) do
    if not writeDeep(f.path, f.code) or X.readFile(f.path) ~= f.code then
      rollback()
      return false, "Ecriture impossible : " .. f.path .. " (version precedente restauree)."
    end
  end
  return true
end

local function restoreBackup()
  if not fs.isDir(paths.BACKUP_DIR) then return false end
  walk(paths.BACKUP_DIR, function(r)
    local d = X.readFile(fs.combine(paths.BACKUP_DIR, r))
    if d then writeDeep(r, d) end
  end)
  return true
end

local function appUpdate()
  local st = { phase = "idle", msg = "Pret.", remote = nil, rel = nil, prog = 0 }
  local btns = {}

  local function render()
    local w = term.getSize()
    btns = {}
    term.setBackgroundColor(colors.white); term.setTextColor(colors.black); term.clear()
    term.setBackgroundColor(colors.lime)
    for j = 0, 1 do term.setCursorPos(3, 2 + j); term.write("      ") end
    term.setTextColor(colors.black); term.setCursorPos(5, 2); term.write("^^")
    term.setBackgroundColor(colors.white)
    term.setCursorPos(11, 2); term.setTextColor(colors.black); term.write("Mise a jour du systeme")
    term.setCursorPos(11, 3); term.setTextColor(colors.gray); term.write((X.NAME .. " " .. VERSION .. " (installe)"):sub(1, w - 11))
    term.setCursorPos(3, 5); term.setTextColor(colors.gray)
    term.write(("Depot : " .. readRepo():gsub("^https?://", "")):sub(1, w - 3))
    local col = colors.black
    if st.phase == "error" then col = colors.red elseif st.phase == "done" then col = colors.green end
    term.setTextColor(col)
    local tw = w - 4
    term.setCursorPos(3, 7); term.write(st.msg:sub(1, tw))
    term.setCursorPos(3, 8); term.write(st.msg:sub(tw + 1, tw * 2))
    term.setCursorPos(3, 10); term.setBackgroundColor(colors.lightGray); term.write(string.rep(" ", tw))
    term.setCursorPos(3, 10); term.setBackgroundColor(colors.blue)
    term.write(string.rep(" ", math.floor(tw * st.prog)))
    term.setBackgroundColor(colors.white); term.setTextColor(colors.gray)
    if st.remote then
      term.setCursorPos(3, 11)
      term.write(("Version distante : " .. st.remote .. "  (" .. #st.rel.files .. " fichiers)"):sub(1, tw))
    end
    local defs = { { " Rechercher ", colors.blue, "check" } }
    if st.rel and st.phase ~= "done" then defs[#defs + 1] = { " Installer ", colors.green, "install" } end
    if fs.isDir(paths.BACKUP_DIR) then defs[#defs + 1] = { " Restaurer ", colors.orange, "restore" } end
    if st.phase == "done" then defs[#defs + 1] = { " Redemarrer ", colors.red, "reboot" } end
    local x = 3
    for _, d in ipairs(defs) do
      term.setCursorPos(x, 13); term.setBackgroundColor(d[2]); term.setTextColor(colors.white); term.write(d[1])
      btns[#btns + 1] = { x, x + #d[1] - 1, d[3] }
      x = x + #d[1] + 1
    end
  end

  local function check()
    st.phase = "checking"; st.rel = nil; st.remote = nil; st.prog = 0.02
    local rel, err = fetchRelease(function(p, m) st.prog = p; st.msg = "Telechargement : " .. tostring(m); render() end)
    if not rel then
      st.phase = "error"; st.msg = tostring(err); st.prog = 0
      return
    end
    st.rel, st.remote, st.phase, st.prog = rel, rel.version, "ready", 0.7
    if X.verCmp(rel.version, VERSION) > 0 then
      st.msg = "Mise a jour disponible : " .. VERSION .. " -> " .. rel.version
    else
      st.msg = "Votre systeme est a jour (version " .. VERSION .. "). Vous pouvez reinstaller."
    end
  end

  local function install()
    if not st.rel then return end
    st.phase = "installing"; st.msg = "Installation en cours..."; st.prog = 0.85; render()
    local ok, err = installRelease(st.rel)
    if ok then
      st.phase = "done"; st.prog = 1; st.msg = "Mise a jour installee ! Redemarrez pour l'appliquer."
    else
      st.phase = "error"; st.prog = 0; st.msg = tostring(err)
    end
  end

  st.msg = "Recherche des mises a jour..."; render()
  check()
  while true do
    render()
    local e, a, b, c = os.pullEvent()
    if e == "mouse_click" and c == 13 then
      for _, bt in ipairs(btns) do
        if b >= bt[1] and b <= bt[2] then
          if bt[3] == "check" then st.msg = "Recherche..."; render(); check()
          elseif bt[3] == "install" then install()
          elseif bt[3] == "restore" then
            if restoreBackup() then
              st.phase = "done"; st.prog = 1; st.msg = "Version precedente restauree. Redemarrez pour l'appliquer."
            else
              st.phase = "error"; st.prog = 0; st.msg = "Aucune sauvegarde disponible."
            end
          elseif bt[3] == "reboot" then sysReboot() end
          break
        end
      end
    end
  end
end


-- --------------------------------------------------------------- registre --
X.fundamental = {
  { id = "terminal", name = "Terminal", icon = ">_", col = colors.black, tc = colors.lime, w = 46, h = 16,
    fn = appTerminal, kind = "fundamental", author = "Exelia", description = "Terminal limite au dossier User." },
  { id = "explorer", name = "Explorateur", icon = "[]", col = colors.yellow, tc = colors.black, w = 51, h = 18,
    fn = appExplorer, kind = "fundamental", author = "Exelia", description = "Parcourir et gerer vos fichiers." },
  { id = "settings", name = "Parametres", icon = "**", col = colors.lightGray, tc = colors.black, w = 40, h = 15,
    fn = appSettings, kind = "fundamental", author = "Exelia", description = "Fond d'ecran, horloge, compte." },
  { id = "update", name = "Mise a jour", icon = "^^", col = colors.lime, tc = colors.black, w = 46, h = 15,
    fn = appUpdate, kind = "fundamental", author = "Exelia", description = "Met a jour Exelia OS depuis GitHub." },
  { id = "info", name = "Infos", icon = "i", col = colors.blue, tc = colors.white, w = 46, h = 15,
    fn = appInfo, kind = "fundamental", author = "Exelia", description = "Informations sur le systeme." },
}
