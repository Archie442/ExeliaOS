-- ============================================================================
--  Exelia OS - System/run/main.lua
--  Processus principal : fenetres, evenements (souris, clavier, minuteurs),
--  connexion, menu demarrer et boucle de l'interface.
-- ============================================================================
local X = ...
local fs, S, cfg, appList, wins, notifs, unpack = X.fs, X.S, X.cfg, X.appList, X.wins, X.notifs, X.unpack
local native = X.native
local W, H = X.W, X.H
local VERSION = X.VERSION
local root = X.root
local WELCOME_TIME, LAUNCH = X.WELCOME_TIME, X.LAUNCH

-- fonctions des autres composants
local hash, saveCfg, loadCfg, ensureStructure, refreshApps = X.hash, X.saveCfg, X.loadCfg, X.ensureStructure, X.refreshApps
local newLock, startItems, startGeom, openMenu = X.newLock, X.startItems, X.startGeom, X.openMenu
local boot, draw, applyPalette, applyWallpaper = X.boot, X.draw, X.applyPalette, X.applyWallpaper

S.focused, S.mouseTarget, S.drag, S.curWin = nil, nil, nil, nil
S.lock, S.welcome, S.animTimer = nil, nil, nil
local nextId = 1

local function topVisible()
  for i = #wins, 1, -1 do if not wins[i].min then return wins[i] end end
  return nil
end

local function focus(w)
  for i, v in ipairs(wins) do if v == w then table.remove(wins, i) break end end
  wins[#wins + 1] = w
  S.focused = w
  w.min = false
end

local function resume(w, ev)
  if w.dead then return end
  if type(w.filter) == "string" and ev[1] ~= w.filter and ev[1] ~= "terminate" then return end
  local old = term.redirect(w.win)
  local prevWin = S.curWin
  S.curWin = w
  local ok, res = coroutine.resume(w.co, unpack(ev, 1, ev.n or #ev))
  S.curWin = prevWin
  term.redirect(old)
  if ok then w.filter = res else w.dead = true; w.err = res end
  if coroutine.status(w.co) == "dead" then w.dead = true end
end

local function spawn(title, fn, w, h, ...)
  local args = table.pack(...)
  w = math.max(12, math.min(w or 40, W))
  h = math.max(5, math.min(h or 14, H - 1))
  local n = #wins
  local x = math.max(1, math.min(2 + (n * 3) % 12, W - w + 1))
  local y = math.max(2, math.min(2 + n % 4, H + 1 - h))
  local win = window.create(root, x, y + 1, w, h - 1, false)
  local o = { id = nextId, title = title, x = x, y = y, w = w, h = h, win = win, min = false }
  nextId = nextId + 1
  for _, a in ipairs(appList) do if a.fn == fn then o.app = a end end
  o.co = coroutine.create(function() fn(unpack(args, 1, args.n)) end)
  focus(o)
  resume(o, { n = 0 })
  return o
end

local function msgbox(title, text)
  text = tostring(text):sub(1, 160)
  spawn(title, function()
    while true do
      local w, h = term.getSize()
      term.setBackgroundColor(colors.white); term.setTextColor(colors.black); term.clear()
      term.setCursorPos(1, 1); print(text)
      local bx = math.floor((w - 6) / 2) + 1
      term.setCursorPos(bx, h); term.setBackgroundColor(colors.green)
      term.setTextColor(colors.white); term.write("  OK  ")
      local e, a, b, c = os.pullEvent()
      if e == "key" and (a == keys.enter or a == keys.space) then return end
      if e == "mouse_click" and c == h and b >= bx and b <= bx + 5 then return end
    end
  end, 38, 9)
end

local function toggleMax(w)
  if w.max then
    w.x, w.y, w.w, w.h = w.sv.x, w.sv.y, w.sv.w, w.sv.h
    w.max = false
  else
    w.sv = { x = w.x, y = w.y, w = w.w, h = w.h }
    w.x, w.y, w.w, w.h = 1, 2, W, H - 1
    w.max = true
  end
  w.win.reposition(w.x, w.y + 1, w.w, w.h - 1)
  resume(w, { "term_resize", n = 1 })
end



-- lancement depuis le menu demarrer
local function launchApp(a)
  S.menuOpen = false; S.menuQuery = ""
  spawn(a.name, a.fn, a.w, a.h)
end

-- ============================================================================
--  Evenements
-- ============================================================================
local function unlock(showWelcome)
  S.lock = nil; S.menuOpen = false; S.menuQuery = ""
  if showWelcome then S.welcome = os.clock() + WELCOME_TIME; S.animTimer = os.startTimer(0.09) end
end

local function lockSubmit()
  local f = S.lock.f[S.lock.cur]
  if S.lock.mode == "setup" then
    if S.lock.cur < #S.lock.f then S.lock.cur = S.lock.cur + 1; return end
    local user = S.lock.f[1].v:gsub("^%s+", ""):gsub("%s+$", "")
    if user == "" then
      S.lock.msg = "Nom d'utilisateur requis"; S.lock.cur = 1
    elseif S.lock.f[2].v ~= S.lock.f[3].v then
      S.lock.msg = "Mots de passe differents"
      S.lock.f[2].v, S.lock.f[3].v = "", ""; S.lock.cur = 2
    else
      cfg.user = user
      cfg.pass = (S.lock.f[2].v == "") and "" or hash(S.lock.f[2].v)
      saveCfg()
      unlock(false)
      msgbox("Bienvenue", "Bienvenue sur Exelia OS, " .. user .. " ! Cliquez sur [ Exelia OS ] en haut a gauche pour ouvrir la liste de vos applications, ou installez-en de nouvelles avec l'App Store.")
    end
  else
    if cfg.pass == "" or hash(f.v) == cfg.pass then
      unlock(true)
    else
      S.lock.msg = "Mot de passe incorrect"; f.v = ""
    end
  end
end

local function lockEvent(ev)
  local e = ev[1]
  local f = S.lock.f[S.lock.cur]
  if e == "char" then
    f.v = f.v .. ev[2]; S.lock.msg = ""
  elseif e == "paste" then
    f.v = f.v .. (ev[2]:gsub("[\r\n]", ""))
  elseif e == "key" then
    local k = ev[2]
    if k == keys.backspace then f.v = f.v:sub(1, -2)
    elseif (k == keys.tab or k == keys.down) and #S.lock.f > 1 then S.lock.cur = S.lock.cur % #S.lock.f + 1
    elseif k == keys.up and #S.lock.f > 1 then S.lock.cur = (S.lock.cur - 2) % #S.lock.f + 1
    elseif k == keys.enter then lockSubmit() end
  end
end

local function lockClick(x, y)
  local hit = S.lock.hit
  if not hit then return end
  if y == H then
    for _, b in ipairs(hit.btn) do
      if x >= b.x1 and x <= b.x2 then b.fn() return end
    end
  end
  if hit.arrow and y == hit.arrow.y and x >= hit.arrow.x1 and x <= hit.arrow.x2 then lockSubmit() return end
  for i, fh in ipairs(hit.fields) do
    if y == fh.y and x >= fh.x and x < fh.x + fh.w then S.lock.cur = i end
  end
end

local function startClick(x, y)
  local h = S.startHit
  if not h then return end
  for _, t in ipairs(h.tiles) do
    if x >= t.x and x < t.x + t.w and y >= t.y and y < t.y + t.h then launchApp(t.app) return end
  end
  for _, f in ipairs(h.foot) do
    if y == f.y and x >= f.x1 and x <= f.x2 then S.menuOpen = false; f.fn() return end
  end
end

local function startKey(ev)
  local e = ev[1]
  if e == "char" then
    S.menuQuery = S.menuQuery .. ev[2]; S.menuSel = 1; S.menuScroll = 0
  elseif e == "paste" then
    S.menuQuery = S.menuQuery .. (ev[2]:gsub("[\r\n]", "")); S.menuSel = 1; S.menuScroll = 0
  elseif e == "key" then
    local k = ev[2]
    if k == keys.backspace then S.menuQuery = S.menuQuery:sub(1, -2); S.menuSel = 1; S.menuScroll = 0
    elseif k == keys.up then S.menuSel = S.menuSel - 1
    elseif k == keys.down then S.menuSel = S.menuSel + 1
    elseif k == keys.enter then
      local t = startItems()
      if t[S.menuSel] then launchApp(t[S.menuSel]) end
    end
  end
end

local function startScroll(dir)
  local items = startItems()
  local _, _, _, _, rows = startGeom()
  S.menuScroll = math.max(0, math.min(math.max(0, #items - rows), S.menuScroll + dir))
  S.menuSel = math.max(S.menuScroll + 1, math.min(S.menuSel, S.menuScroll + rows))
end

local function handleClick(btn, x, y)
  if S.lock or (S.welcome and os.clock() < S.welcome) then return end
  for _, nh in ipairs(S.notifHit) do
    if x >= nh.x1 and x <= nh.x2 and y >= nh.y1 and y <= nh.y2 then
      for i, n in ipairs(notifs) do if n == nh.n then table.remove(notifs, i) break end end
      return
    end
  end
  if S.menuOpen then
    local px, py, pw, ph = startGeom()
    if x >= px and x < px + pw and y >= py and y < py + ph then startClick(x, y) return end
    S.menuOpen = false
    if y == 1 and x <= #LAUNCH then return end
  elseif y == 1 and x <= #LAUNCH then
    openMenu(); return
  end
  if y == 1 then
    for _, t in ipairs(S.tabHit) do
      if x >= t.x1 and x <= t.x2 then
        if t.win == S.focused and not t.win.min then t.win.min = true; S.focused = topVisible()
        else focus(t.win) end
        return
      end
    end
    return
  end
  for i = #wins, 1, -1 do
    local w = wins[i]
    if not w.min and x >= w.x and x < w.x + w.w and y >= w.y and y < w.y + w.h then
      focus(w)
      if y == w.y then
        local rx = x - w.x
        if rx == 1 then w.dead = true
        elseif rx == 3 then w.min = true; S.focused = topVisible()
        elseif rx == 5 then toggleMax(w)
        elseif not w.max then S.drag = { w = w, dx = x - w.x } end
      else
        S.mouseTarget = w
        resume(w, { "mouse_click", btn, x - w.x + 1, y - w.y, n = 4 })
      end
      return
    end
  end
end

local function reap()
  local errors = {}
  for i = #wins, 1, -1 do
    local w = wins[i]
    if w.dead then
      table.remove(wins, i)
      if S.focused == w then S.focused = topVisible() end
      if S.mouseTarget == w then S.mouseTarget = nil end
      if S.drag and S.drag.w == w then S.drag = nil end
      if w.err and not tostring(w.err):find("Terminated") then
        errors[#errors + 1] = { w.title, w.err }
      end
    end
  end
  for _, er in ipairs(errors) do msgbox("Erreur", er[1] .. " : " .. tostring(er[2])) end
end



-- ------------------------------------------------- lancement d'applications --
-- Lance une application par son identifiant (ex. "editor", "update") avec des arguments
local function launchById(id, ...)
  for _, a in ipairs(appList) do
    if a.id == id then
      S.menuOpen = false
      return spawn(a.name, a.fn, a.w, a.h, ...)
    end
  end
  return nil
end

-- ------------------------------------------------------------- demarrage --
local function start()
  ensureStructure()
  loadCfg()
  applyPalette()
  applyWallpaper(cfg.wall)
  refreshApps()
  boot()
  S.lock = newLock()
  local clockTimer = os.startTimer(1)
  local bootOk = false
  while true do
    draw()
    if not bootOk then   -- demarrage reussi : on oublie la restauration automatique
      bootOk = true
      X.booted = true
      pcall(fs.delete, X.paths.PENDING_FILE)
    end
    local ev = table.pack(os.pullEventRaw())
    local e = ev[1]
    if e == "terminate" then
      if not S.lock and S.focused then resume(S.focused, ev) end
    elseif e == "term_resize" then
      X.W, X.H = native.getSize()
      W, H = X.W, X.H
      X.onResize(W, H)
    elseif e == "timer" and ev[2] == clockTimer then
      clockTimer = os.startTimer(1) -- rafraichit l'horloge
    elseif e == "timer" and S.animTimer and ev[2] == S.animTimer then
      if S.welcome and os.clock() < S.welcome then S.animTimer = os.startTimer(0.09) else S.animTimer = nil end
    elseif e == "mouse_click" then
      if S.lock then lockClick(ev[3], ev[4]) else handleClick(ev[2], ev[3], ev[4]) end
    elseif e == "mouse_drag" then
      if S.drag then
        local w = S.drag.w
        local nx = math.max(1, math.min(W - w.w + 1, ev[3] - S.drag.dx))
        local ny = math.max(2, math.min(H + 1 - w.h, ev[4]))
        w.x, w.y = nx, ny
        w.win.reposition(nx, ny + 1)
      elseif S.mouseTarget then
        resume(S.mouseTarget, { "mouse_drag", ev[2], ev[3] - S.mouseTarget.x + 1, ev[4] - S.mouseTarget.y, n = 4 })
      end
    elseif e == "mouse_up" then
      if S.drag then S.drag = nil
      elseif S.mouseTarget then
        resume(S.mouseTarget, { "mouse_up", ev[2], ev[3] - S.mouseTarget.x + 1, ev[4] - S.mouseTarget.y, n = 4 })
      end
      S.mouseTarget = nil
    elseif e == "mouse_scroll" then
      if S.menuOpen and not S.lock then
        startScroll(ev[2])
      elseif not S.lock then
        for i = #wins, 1, -1 do
          local w = wins[i]
          if not w.min and ev[3] >= w.x and ev[3] < w.x + w.w and ev[4] > w.y and ev[4] < w.y + w.h then
            resume(w, { "mouse_scroll", ev[2], ev[3] - w.x + 1, ev[4] - w.y, n = 4 })
            break
          end
        end
      end
    elseif e == "key" or e == "char" or e == "key_up" or e == "paste" then
      if S.lock then lockEvent(ev)
      elseif S.menuOpen then startKey(ev)
      elseif S.focused then resume(S.focused, ev) end
    else
      for _, w in ipairs({ unpack(wins) }) do resume(w, ev) end
    end
    reap()
  end
end

X.spawn, X.msgbox, X.focus, X.resume = spawn, msgbox, focus, resume
X.launchById, X.launchApp = launchById, launchApp
X.start = start
