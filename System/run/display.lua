-- ============================================================================
--  Exelia OS - System/run/display.lua
--  Affichage : palette, fond d'ecran, barre de menu, fenetres, menu demarrer,
--  ecran de connexion, notifications et ecran de demarrage.
-- ============================================================================
local X = ...
local fs, S, cfg, appList, wins, notifs, unpack = X.fs, X.S, X.cfg, X.appList, X.wins, X.notifs, X.unpack
local native = X.native
local W, H = X.W, X.H
local VERSION = X.VERSION
S.menuOpen, S.menuQuery, S.menuSel, S.menuScroll = false, "", 1, 0
S.tabHit, S.notifHit = {}, {}

-- Palette "macOS" appliquee a tout le systeme
local basePalette = {
  [colors.black]     = 0x101014,
  [colors.gray]      = 0x48484C,
  [colors.lightGray] = 0xD1D1D6,
  [colors.white]     = 0xF5F5F7,
  [colors.blue]      = 0x0A84FF,
  [colors.cyan]      = 0x40C8E0,
  [colors.lightBlue] = 0x64A8FF,
  [colors.orange]    = 0xFF9F0A,
  [colors.yellow]    = 0xFFD60A,
  [colors.lime]      = 0x30D158,
  [colors.green]     = 0x248A3D,
  [colors.red]       = 0xFF453A,
}
-- Fonds d'ecran : 4 teintes (haut -> bas) stockees dans 4 couleurs de la palette
local wallpapers = {
  { name = "Sonoma",   stops = { 0x2B1055, 0x7B2D8E, 0xE0507A, 0xFFA14A } },
  { name = "Ocean",    stops = { 0x0B1D4A, 0x14558F, 0x2A8FC4, 0x7FD1E8 } },
  { name = "Foret",    stops = { 0x0B2B1F, 0x1B5E3A, 0x3FA66B, 0xA8E6A1 } },
  { name = "Aurore",   stops = { 0x3A1C71, 0xD76D77, 0xFFAF7B, 0xFFE0A3 } },
  { name = "Graphite", stops = { 0x16161A, 0x2A2A30, 0x44444C, 0x6A6A75 } },
}
local wallSlots = { colors.purple, colors.magenta, colors.pink, colors.brown }


-- Saisie sur la derniere ligne de la fenetre courante
local function ask(prompt, default, mask)
  local w, h = term.getSize()
  term.setCursorPos(1, h)
  term.setBackgroundColor(colors.gray)
  term.setTextColor(colors.white)
  term.clearLine()
  term.write(prompt .. " ")
  local r = read(mask, nil, nil, default)
  term.setBackgroundColor(colors.black)
  return r or ""
end

local root = window.create(native, 1, 1, W, H, false) -- tampon d'affichage

local function palSet(c, rgb)
  pcall(native.setPaletteColor, c, rgb)
  pcall(root.setPaletteColor, c, rgb)
end
local function applyPalette()
  for c, rgb in pairs(basePalette) do palSet(c, rgb) end
end
local function applyWallpaper(i)
  local wp = wallpapers[i] or wallpapers[1]
  for k, c in ipairs(wallSlots) do palSet(c, wp.stops[k]) end
end
local function restorePalette()
  for i = 0, 15 do
    local c = 2 ^ i
    pcall(function() native.setPaletteColor(c, term.nativePaletteColor(c)) end)
  end
end
local function sysReboot() restorePalette(); os.reboot() end
local function sysShutdown() restorePalette(); os.shutdown() end

local function pushNotif(appName, title, text)
  notifs[#notifs + 1] = {
    app = tostring(appName or ""), title = tostring(title or ""), text = tostring(text or ""),
    expires = os.clock() + 6,
  }
  if #notifs > 4 then table.remove(notifs, 1) end
end

-- ============================================================================
--  Rendu du bureau (style macOS)
-- ============================================================================
local BL = {}
for i = 0, 15 do BL[2 ^ i] = ("0123456789abcdef"):sub(i + 1, i + 1) end

local function rtext(x, y, s, fg, bg)
  root.setCursorPos(x, y); root.setTextColor(fg); root.setBackgroundColor(bg); root.write(s)
end
local function rfill(x, y, w, h, bg)
  root.setBackgroundColor(bg)
  local s = string.rep(" ", math.max(0, w))
  for j = 0, h - 1 do root.setCursorPos(x, y + j); root.write(s) end
end
-- pastille de texte centree
local function chip(y, text, fg, bg, pad)
  pad = pad or 1
  local w = #text + pad * 2
  local x = math.floor((W - w) / 2) + 1
  rfill(x, y, w, 1, bg)
  rtext(x + pad, y, text, fg, bg)
  return x, w
end

local LAUNCH = " Exelia OS "
local WELCOME_TIME = 1.8

local function newLock()
  if not cfg.user then
    return { mode = "setup", cur = 1, msg = "", f = {
      { l = "Nom d'utilisateur", v = "", m = false },
      { l = "Mot de passe", v = "", m = true },
      { l = "Confirmer le mot de passe", v = "", m = true } } }
  end
  return { mode = "login", cur = 1, msg = "",
           f = { { l = (cfg.pass == "" and "Appuyez sur Entree" or "Mot de passe"), v = "", m = true } } }
end

-- fond d'ecran en degrade (4 teintes + tramage entre les bandes)
local function drawWallpaper(y1, y2)
  local span = math.max(1, y2 - y1)
  for y = y1, y2 do
    local t = (y - y1) / span * 3
    local a = math.min(3, math.floor(t)) + 1
    local fr = t - (a - 1)
    local ca, cb = wallSlots[a], wallSlots[math.min(4, a + 1)]
    local ch, fg, bg
    if a == 4 or fr < 0.34 then ch, fg, bg = " ", "0", BL[ca]
    elseif fr < 0.67 then ch, fg, bg = "\149", BL[ca], BL[cb]
    else ch, fg, bg = " ", "0", BL[cb] end
    root.setCursorPos(1, y)
    root.blit(string.rep(ch, W), string.rep(fg, W), string.rep(bg, W))
  end
end

local bigfont = {
  ["0"] = { "###", "# #", "# #", "# #", "###" },
  ["1"] = { " # ", "## ", " # ", " # ", "###" },
  ["2"] = { "###", "  #", "###", "#  ", "###" },
  ["3"] = { "###", "  #", "###", "  #", "###" },
  ["4"] = { "# #", "# #", "###", "  #", "  #" },
  ["5"] = { "###", "#  ", "###", "  #", "###" },
  ["6"] = { "###", "#  ", "###", "# #", "###" },
  ["7"] = { "###", "  #", "  #", "  #", "  #" },
  ["8"] = { "###", "# #", "###", "# #", "###" },
  ["9"] = { "###", "# #", "###", "  #", "###" },
  [":"] = { " ", "#", " ", "#", " " },
}

local function drawBigClock(y)
  local t = os.time()
  local hh = math.floor(t) % 24
  local mm = math.floor((t - math.floor(t)) * 60)
  local s = string.format("%02d:%02d", hh, mm)
  local sx = (W >= 40) and 2 or 1
  local total = 0
  for i = 1, #s do total = total + #bigfont[s:sub(i, i)][1] * sx end
  total = total + (#s - 1) * sx
  local x = math.floor((W - total) / 2) + 1
  for i = 1, #s do
    local g = bigfont[s:sub(i, i)]
    for r = 1, 5 do
      for c = 1, #g[r] do
        if g[r]:sub(c, c) == "#" then rfill(x + (c - 1) * sx, y + r - 1, sx, 1, colors.white) end
      end
    end
    x = x + #g[1] * sx + sx
  end
end

local function drawAvatar(cx, y, name)
  local x = cx - 2
  rfill(x + 1, y, 3, 1, colors.blue)
  rfill(x, y + 1, 5, 1, colors.blue)
  rfill(x + 1, y + 2, 3, 1, colors.blue)
  rtext(cx, y + 1, (tostring(name):sub(1, 1)):upper(), colors.white, colors.blue)
end

local function drawMenubar()
  rfill(1, 1, W, 1, colors.gray)
  rtext(1, 1, LAUNCH, colors.white, S.menuOpen and colors.cyan or colors.blue)
  local right = (cfg.user and (cfg.user .. "  ") or "") .. "J" .. os.day() .. "  " ..
                textutils.formatTime(os.time(), cfg.clock24) .. " "
  rtext(W - #right + 1, 1, right, colors.lightGray, colors.gray)
  -- onglets des fenetres ouvertes (remplace l'ancien dock)
  S.tabHit = {}
  if not S.lock then
    local x0, x1 = #LAUNCH + 2, W - #right - 1
    local list = {}
    for _, w in ipairs(wins) do list[#list + 1] = w end
    table.sort(list, function(a, b) return a.id < b.id end)
    local avail = x1 - x0 + 1
    if #list > 0 and avail >= 5 then
      local tw = math.max(5, math.min(16, math.floor(avail / #list)))
      for i, w in ipairs(list) do
        local x = x0 + (i - 1) * tw
        if x + tw - 2 > x1 then break end
        local isF = (w == S.focused and not w.min)
        local bg = isF and colors.lightGray or colors.gray
        local fg = isF and colors.black or (w.min and colors.lightGray or colors.white)
        rfill(x, 1, tw - 1, 1, bg)
        rtext(x + 1, 1, w.title:sub(1, tw - 3), fg, bg)
        S.tabHit[#S.tabHit + 1] = { x1 = x, x2 = x + tw - 2, win = w }
      end
    end
  end
end

-- fenetre style macOS : feux tricolores a gauche, titre centre
local function drawWindow(w)
  local isF = (w == S.focused)
  local bg = isF and colors.lightGray or colors.white
  local fg = isF and colors.black or colors.gray
  rfill(w.x, w.y, w.w, 1, bg)
  rtext(w.x + 1, w.y, " ", colors.white, isF and colors.red or colors.lightGray)
  rtext(w.x + 3, w.y, " ", colors.white, isF and colors.yellow or colors.lightGray)
  rtext(w.x + 5, w.y, " ", colors.white, isF and colors.lime or colors.lightGray)
  local t = w.title:sub(1, math.max(0, w.w - 10))
  rtext(w.x + 7 + math.floor((w.w - 8 - #t) / 2), w.y, t, fg, bg)
  w.win.setVisible(true)  -- recopie le contenu dans le tampon
  w.win.setVisible(false)
end

-- ------------------------------------------------------------ Menu demarrer --
local function startItems()
  local q = S.menuQuery:lower()
  local list = {}
  for _, a in ipairs(appList) do
    if q == "" or a.name:lower():find(q, 1, true) then list[#list + 1] = a end
  end
  return list
end

local function startGeom()
  local pw = math.min(34, W - 1)
  local rows = math.max(3, math.min(11, H - 6))
  return 1, 2, pw, rows + 5, rows
end

local function menuClamp(n, rows)
  if S.menuSel > n then S.menuSel = n end
  if S.menuSel < 1 then S.menuSel = 1 end
  if S.menuSel <= S.menuScroll then S.menuScroll = S.menuSel - 1 end
  if S.menuSel > S.menuScroll + rows then S.menuScroll = S.menuSel - rows end
  S.menuScroll = math.max(0, math.min(S.menuScroll, math.max(0, n - rows)))
end

local function openMenu()
  S.menuOpen = true; S.menuQuery = ""; S.menuSel = 1; S.menuScroll = 0
end


-- icone : couleurs propres a l'app integree, sinon icone par defaut grise et noire
local function drawAppIcon(x, y, a, bg)
  if a.col then
    rfill(x, y, 4, 1, a.col)
    rtext(x + math.floor((4 - #a.icon) / 2), y, a.icon, a.tc, a.col)
  else
    rtext(x, y, " ", colors.black, colors.black)
    rtext(x + 1, y, " " .. a.name:sub(1, 1):upper() .. " ", colors.black, colors.lightGray)
  end
end

local function drawStart()
  local items = startItems()
  local px, py, pw, ph, rows = startGeom()
  menuClamp(#items, rows)
  rfill(px, py, pw, ph, colors.gray)
  local name = tostring(cfg.user or "Invite")
  rtext(px + 1, py, " " .. name:sub(1, 1):upper() .. " ", colors.white, colors.blue)
  rtext(px + 5, py, name:sub(1, math.max(1, pw - 14)), colors.white, colors.gray)
  local ver = "v" .. VERSION
  rtext(px + pw - #ver - 1, py, ver, colors.lightGray, colors.gray)
  rfill(px + 1, py + 1, pw - 2, 1, colors.black)
  if S.menuQuery == "" then
    rtext(px + 2, py + 1, ("Rechercher une application..."):sub(1, pw - 5), colors.lightGray, colors.black)
  else
    rtext(px + 2, py + 1, S.menuQuery:sub(-(pw - 5)), colors.white, colors.black)
  end
  S.startHit = { tiles = {}, foot = {} }
  for r = 1, rows do
    local idx = S.menuScroll + r
    local a = items[idx]
    if not a then break end
    local y = py + 2 + r
    local bg = (idx == S.menuSel) and colors.blue or colors.gray
    rfill(px + 1, y, pw - 3, 1, bg)
    drawAppIcon(px + 2, y, a, bg)
    rtext(px + 7, y, a.name:sub(1, math.max(1, pw - 10)), colors.white, bg)
    S.startHit.tiles[#S.startHit.tiles + 1] = { x = px + 1, y = y, w = pw - 3, h = 1, app = a }
  end
  if #items > rows then   -- barre de defilement
    local thumb = math.max(1, math.floor(rows * rows / #items))
    local top = math.floor(S.menuScroll * (rows - thumb) / math.max(1, #items - rows))
    for r = 0, rows - 1 do
      local on = r >= top and r < top + thumb
      rtext(px + pw - 2, py + 3 + r, " ", colors.white, on and colors.lightGray or colors.black)
    end
  end
  if #items == 0 then rtext(px + 2, py + 4, "Aucun resultat", colors.lightGray, colors.gray) end
  local fy = py + ph - 1
  local short = pw < 30
  local defs = {
    { short and " L " or " Verrou ", colors.lightGray, colors.black, function() S.lock = newLock() end },
    { short and " R " or " Reboot ", colors.orange, colors.black, sysReboot },
    { short and " O " or " Off ", colors.red, colors.white, sysShutdown },
    { short and " U " or " MAJ ", colors.lime, colors.black,
      function() X.launchById("update") end },
  }
  local fx = px + 1
  for _, d in ipairs(defs) do
    rtext(fx, fy, d[1], d[3], d[2])
    S.startHit.foot[#S.startHit.foot + 1] = { x1 = fx, x2 = fx + #d[1] - 1, y = fy, fn = d[4] }
    fx = fx + #d[1] + 1
  end
end

-- ------------------------------------------------------- Ecran de connexion --
local function pill(y, f, active, withArrow)
  local pw = math.min(28, W - 4)
  local x = math.floor((W - pw) / 2) + 1
  local bg = active and colors.white or colors.lightGray
  rfill(x, y, pw, 1, bg)
  local shown = f.m and string.rep("*", #f.v) or f.v
  local tw = pw - (withArrow and 6 or 2)
  if #shown == 0 then
    rtext(x + 1, y, f.l:sub(1, tw), colors.gray, bg)
  else
    rtext(x + 1, y, shown:sub(-(tw - 1)), colors.black, bg)
  end
  if withArrow then rtext(x + pw - 4, y, " > ", colors.white, colors.blue) end
  return x, pw, shown, tw
end

local function drawLock()
  drawWallpaper(1, H)
  drawBigClock(3)
  chip(9, "Jour " .. os.day(), colors.white, colors.gray)
  drawMenubar()
  local cx = math.floor(W / 2) + 1
  S.lock.hit = { fields = {}, btn = {} }
  local curX, curY
  if S.lock.mode == "login" then
    drawAvatar(cx, 11, cfg.user or "?")
    chip(14, tostring(cfg.user), colors.white, colors.gray)
    local x, pw, shown, tw = pill(16, S.lock.f[1], true, true)
    S.lock.hit.arrow = { x1 = x + pw - 4, x2 = x + pw - 2, y = 16 }
    curX, curY = x + 1 + math.min(#shown, tw - 1), 16
  else
    chip(10, "Bienvenue sur Exelia OS", colors.white, colors.blue, 2)
    for i, f in ipairs(S.lock.f) do
      local y = 12 + (i - 1) * 2
      local x, pw, shown, tw = pill(y, f, i == S.lock.cur, false)
      S.lock.hit.fields[i] = { x = x, w = pw, y = y }
      if i == S.lock.cur then curX, curY = x + 1 + math.min(#shown, tw - 1), y end
    end
  end
  if S.lock.msg ~= "" then chip(18, S.lock.msg, colors.white, colors.red) end
  local b1, b2 = " Redemarrer ", " Eteindre "
  local x = math.floor((W - (#b1 + #b2 + 2)) / 2) + 1
  rtext(x, H, b1, colors.white, colors.gray)
  rtext(x + #b1 + 2, H, b2, colors.white, colors.gray)
  S.lock.hit.btn = {
    { x1 = x, x2 = x + #b1 - 1, fn = sysReboot },
    { x1 = x + #b1 + 2, x2 = x + #b1 + #b2 + 1, fn = sysShutdown },
  }
  if curX then
    root.setCursorPos(curX, curY); root.setTextColor(colors.black); root.setCursorBlink(true)
  end
end

-- animation de connexion : roue de chargement qui tourne (8 points + traine)
local spinPts = { {0,-2}, {2,-1}, {3,0}, {2,1}, {0,2}, {-2,1}, {-3,0}, {-2,-1} }
local function drawWelcome()
  drawWallpaper(1, H)
  drawMenubar()
  local cx, cy = math.floor(W / 2) + 1, math.floor(H / 2) + 1
  -- fond arrondi
  rfill(cx - 7, cy - 2, 15, 5, colors.black)
  rfill(cx - 5, cy - 3, 11, 1, colors.black)
  rfill(cx - 5, cy + 3, 11, 1, colors.black)
  local head = math.floor((os.clock() - (S.welcome - WELCOME_TIME)) / 0.09) % 8
  for i, p in ipairs(spinPts) do
    local age = (head - (i - 1)) % 8
    local col = colors.gray
    if age == 0 then col = colors.white
    elseif age <= 2 then col = colors.lightGray end
    rfill(cx + p[1] - 1, cy + p[2], 2, 1, col)
  end
end

local function drawNotifs()
  S.notifHit = {}
  local now = os.clock()
  for i = #notifs, 1, -1 do if notifs[i].expires < now then table.remove(notifs, i) end end
  local nw = math.min(30, W - 2)
  local x, y = W - nw, 3
  for _, n in ipairs(notifs) do
    if y + 3 > H then break end
    rfill(x, y, nw, 4, colors.gray)
    rfill(x, y, 1, 4, colors.blue)
    rtext(x + 2, y, n.app:sub(1, nw - 6), colors.lightGray, colors.gray)
    rtext(x + nw - 2, y, "x", colors.lightGray, colors.gray)
    rtext(x + 2, y + 1, n.title:sub(1, nw - 3), colors.white, colors.gray)
    rtext(x + 2, y + 2, n.text:sub(1, nw - 3), colors.lightGray, colors.gray)
    rtext(x + 2, y + 3, n.text:sub(nw - 2, 2 * (nw - 3)), colors.lightGray, colors.gray)
    S.notifHit[#S.notifHit + 1] = { x1 = x, x2 = x + nw - 1, y1 = y, y2 = y + 3, n = n }
    y = y + 5
  end
end

local function draw()
  root.setCursorBlink(false)
  if S.lock then
    drawLock()
  elseif S.welcome and os.clock() < S.welcome then
    drawWelcome()
  else
    S.welcome = nil
    drawWallpaper(2, H)
    for _, w in ipairs(wins) do if not w.min then drawWindow(w) end end
    drawMenubar()
    if S.menuOpen then drawStart() end
    drawNotifs()
    if S.menuOpen then
      local px, py, pw = startGeom()
      root.setCursorPos(px + 2 + math.min(#S.menuQuery, pw - 5), py + 1)
      root.setTextColor(colors.white); root.setCursorBlink(true)
    elseif S.focused and not S.focused.min then
      local cx, cy = S.focused.win.getCursorPos()
      if S.focused.win.getCursorBlink() then
        root.setCursorPos(S.focused.x + cx - 1, S.focused.y + cy)
        root.setTextColor(S.focused.win.getTextColor())
        root.setCursorBlink(true)
      end
    end
  end
  root.setVisible(true)
  root.setVisible(false)
end


local function boot()
  native.setBackgroundColor(colors.black); native.clear()
  local glyphs = {
    { [=[ _____ ]=], [=[| ____|]=], [=[|  _|  ]=], [=[| |___ ]=], [=[|_____|]=] },
    { [=[      ]=], [=[__  __]=], [=[\ \/ /]=], [=[ >  < ]=], [=[/_/\_\]=] },
    { [=[      ]=], [=[  ___ ]=], [=[ / _ \]=], [=[|  __/]=], [=[ \___|]=] },
    { [=[ _ ]=], [=[| |]=], [=[| |]=], [=[| |]=], [=[|_|]=] },
    { [=[ _ ]=], [=[(_)]=], [=[| |]=], [=[| |]=], [=[|_|]=] },
    { [=[       ]=], [=[  __ _ ]=], [=[ / _` |]=], [=[| (_| |]=], [=[ \__,_|]=] },
    { [=[  ]=], [=[  ]=], [=[  ]=], [=[  ]=], [=[  ]=] },
    { [=[  ___  ]=], [=[ / _ \ ]=], [=[| | | |]=], [=[| |_| |]=], [=[ \___/ ]=] },
    { [=[ ____  ]=], [=[/ ___| ]=], [=[\___ \ ]=], [=[ ___) |]=], [=[|____/ ]=] },
  }
  local logo = {}
  for r = 1, 5 do
    local line = ""
    for _, g in ipairs(glyphs) do
      local wmax = 0
      for _, row in ipairs(g) do wmax = math.max(wmax, #row) end
      line = line .. g[r] .. string.rep(" ", wmax - #g[r])
    end
    logo[r] = line
  end
  if W < #logo[1] then logo = { "E x e l i a   O S" } end
  local top = math.max(1, math.floor(H / 2) - 6)
  native.setTextColor(colors.white)
  for i, l in ipairs(logo) do
    native.setCursorPos(math.max(1, math.floor((W - #l) / 2) + 1), top + i - 1); native.write(l)
  end
  local sub = "Version " .. VERSION
  native.setTextColor(colors.lightGray)
  native.setCursorPos(math.max(1, math.floor((W - #sub) / 2) + 1), top + 6); native.write(sub)
  local steps = { "Chargement du noyau...", "Montage du systeme de fichiers...",
    "Application du theme...", "Demarrage du gestionnaire de fenetres...", "Pret." }
  local bw = math.min(26, W - 4)
  local bx = math.floor((W - bw) / 2) + 1
  for i, s in ipairs(steps) do
    native.setCursorPos(1, top + 9); native.setBackgroundColor(colors.black); native.clearLine()
    native.setTextColor(colors.gray)
    native.setCursorPos(math.max(1, math.floor((W - #s) / 2) + 1), top + 9); native.write(s)
    native.setCursorPos(bx, top + 8)
    native.setBackgroundColor(colors.gray); native.write(string.rep(" ", bw))
    native.setCursorPos(bx, top + 8)
    native.setBackgroundColor(colors.white); native.write(string.rep(" ", math.floor(bw * i / #steps)))
    sleep(0.25)
  end
  native.setBackgroundColor(colors.black); native.clear()
end

-- l'ecran a ete redimensionne
local function onResize(w, h)
  W, H = w, h
  root.reposition(1, 1, w, h)
end

X.root, X.wallpapers, X.WELCOME_TIME, X.LAUNCH = root, wallpapers, WELCOME_TIME, LAUNCH
X.ask, X.pushNotif, X.onResize = ask, pushNotif, onResize
X.applyPalette, X.applyWallpaper, X.restorePalette = applyPalette, applyWallpaper, restorePalette
X.sysReboot, X.sysShutdown = sysReboot, sysShutdown
X.newLock, X.startItems, X.startGeom, X.openMenu = newLock, startItems, startGeom, openMenu
X.draw, X.boot = draw, boot
