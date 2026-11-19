--@name App Store
--@icon AS
--@color lightBlue
--@textcolor black
--@size 50x18
--@author Exelia
--@description Installer des applications (catalogue public ou lien direct).
-- App Store - application integree d'Exelia OS (ExeliaScript)
app = exelia.getProgram(app)
app.version = "1.0.0"
app.minOsVersion = 4.0
display = app.getObject(display)
local system = exelia.system
local httpGetText, sanitizeId, resolveSource, stamp = system.httpGet, system.sanitizeId, system.resolveSource, system.stamp
local STORE_URL = system.storeUrl
local STORE_CODE = STORE_URL:match("/raw/(%w+)") or "?"
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function installApp(id, meta, src) return system.installProgram(id, meta, src) end
local function uninstallApp(id) system.uninstallProgram(id) end
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

local function runStore()
  local tab = 1
  local reg, regErr
  local sel, scroll = { 1, 1, 1 }, { 0, 0, 0 }
  local status, statusCol = "Attention : n'installez que des apps de confiance.", colors.orange
  local btns = {}
  local doInstall, doUninstall, doLaunch, doUpdate, doLink, loadRegistry

  local function setStatus(m, c) status, statusCol = m, c or colors.gray end

  local function items()
    if tab == 1 then return reg or {} end
    if tab == 3 then
      local list = {}
      for _, a in ipairs(system.listPrograms()) do list[#list + 1] = a end
      return list
    end
    return {}
  end

  local function geom()
    local w, h = term.getSize()
    return w, h, 3, math.max(3, h - 9)
  end

  local function render()
    local w, h, listTop, listRows = geom()
    btns = {}
    local function put(x, y, s, fg, bg)
      term.setCursorPos(x, y); term.setTextColor(fg); term.setBackgroundColor(bg); term.write(s)
    end
    local function button(x, y, s, bg, fn)
      put(x, y, s, colors.white, bg); btns[#btns + 1] = { x, x + #s - 1, y, fn }
    end
    term.setBackgroundColor(colors.white); term.clear()
    put(1, 1, string.rep(" ", w), colors.black, colors.lightGray)
    local x = 1
    for i, t in ipairs({ " Public ", " Lien ", " Installees " }) do
      put(x, 1, t, tab == i and colors.white or colors.black, tab == i and colors.blue or colors.lightGray)
      btns[#btns + 1] = { x, x + #t - 1, 1, function() tab = i end }
      x = x + #t
    end
    local inst = {}
    for _, a in ipairs(system.listPrograms()) do inst[a.id] = a end
    local dy = listTop + listRows
    if tab ~= 2 then
      local list = items()
      local info, col = "", colors.gray
      if tab == 1 then
        if regErr then info, col = regErr, colors.red
        elseif not reg then info = "Chargement du catalogue..."
        else info = #reg .. " application(s) - pastebin.com/" .. STORE_CODE end
      else
        info = #list .. " programme(s) installe(s)"
      end
      put(2, 2, info:sub(1, w - 2), col, colors.white)
      local s = math.max(1, math.min(sel[tab], #list))
      sel[tab] = s
      local sc = scroll[tab]
      if s <= sc then sc = s - 1 end
      if s > sc + listRows then sc = s - listRows end
      sc = math.max(0, math.min(sc, math.max(0, #list - listRows)))
      scroll[tab] = sc
      for r = 1, listRows do
        local it = list[sc + r]
        local y = listTop + r - 1
        local isSel = (sc + r == s)
        local bg = isSel and colors.blue or colors.white
        put(1, y, string.rep(" ", w), colors.black, bg)
        if it then
          put(2, y, it.name:sub(1, math.max(1, w - 14)), isSel and colors.white or colors.black, bg)
          if tab == 1 and inst[it.id] then
            put(w - 8, y, "installe", isSel and colors.white or colors.green, bg)
          end
        end
      end
      put(1, dy, string.rep("-", w), colors.lightGray, colors.white)
      local it = list[s]
      local bx = 2
      local function nextBtn(label, bg, fn) button(bx, dy + 4, label, bg, fn); bx = bx + #label + 1 end
      if it then
        put(2, dy + 1, (it.name .. "  par " .. tostring(it.author or "?")):sub(1, w - 2), colors.black, colors.white)
        local desc = tostring(it.description or "")
        put(2, dy + 2, desc:sub(1, w - 2), colors.gray, colors.white)
        put(2, dy + 3, desc:sub(w - 1, 2 * (w - 2)), colors.gray, colors.white)
        if tab == 1 then
          nextBtn(inst[it.id] and " Reinstaller " or " Installer ", colors.green, doInstall)
          if inst[it.id] then nextBtn(" Desinstaller ", colors.red, doUninstall) end
        else
          nextBtn(" Lancer ", colors.green, doLaunch)
          nextBtn(" Mettre a jour ", colors.blue, doUpdate)
          nextBtn(" Desinstaller ", colors.red, doUninstall)
        end
      end
      if tab == 1 then nextBtn(" Actualiser ", colors.blue, loadRegistry) end
    else
      put(2, 3, "Telecharger une application depuis un lien", colors.black, colors.white)
      put(2, 5, "Formats acceptes :", colors.gray, colors.white)
      put(2, 6, ("- un code Pastebin (ex : aB3dE5fG)"):sub(1, w - 2), colors.gray, colors.white)
      put(2, 7, ("- un lien pastebin.com/..."):sub(1, w - 2), colors.gray, colors.white)
      put(2, 8, ("- un lien direct http(s) vers un fichier .as"):sub(1, w - 2), colors.gray, colors.white)
      button(2, 10, " Entrer un lien ", colors.blue, doLink)
      put(2, 12, ("L'app sera ajoutee a vos programmes."):sub(1, w - 2), colors.gray, colors.white)
    end
    put(2, dy + 5, status:sub(1, w - 2), statusCol, colors.white)
  end

  loadRegistry = function()
    reg, regErr = nil, nil
    setStatus("Chargement du catalogue...", colors.gray); render()
    local body, err = httpGetText(STORE_URL .. "?cb=" .. stamp())
    if not body then regErr = err; setStatus("", colors.gray); return end
    local data = textutils.unserializeJSON(body)
    if type(data) ~= "table" then
      -- tolerance : virgules manquantes entre les champs
      local fixed = body:gsub('"%s*\n(%s*")', '",\n%1'):gsub('}%s*\n(%s*")', '},\n%1')
      data = textutils.unserializeJSON(fixed)
    end
    if type(data) ~= "table" then regErr = "Catalogue illisible (JSON invalide)."; setStatus("", colors.gray); return end
    reg = {}
    for id, v in pairs(data) do
      if type(v) == "table" and v.pastebin then
        reg[#reg + 1] = {
          id = sanitizeId(id), name = tostring(v.name or id), author = tostring(v.author or "?"),
          description = tostring(v.description or ""), pastebin = tostring(v.pastebin),
        }
      end
    end
    table.sort(reg, function(a, b) return a.name:lower() < b.name:lower() end)
    setStatus("Attention : n'installez que des apps de confiance.", colors.orange)
  end

  doInstall = function()
    local it = items()[sel[tab]]
    if not it then return end
    setStatus("Telechargement de " .. it.name .. "...", colors.gray); render()
    local ok, res = installApp(it.id, { name = it.name, author = it.author, description = it.description }, it.pastebin)
    if ok then setStatus(it.name .. " installe : " .. res, colors.green) else setStatus(tostring(res), colors.red) end
  end

  doUninstall = function()
    local it = items()[sel[tab]]
    if not it then return end
    if ask("Desinstaller " .. it.name .. " ? (o/n)") == "o" then
      uninstallApp(it.id)
      setStatus(it.name .. " desinstalle.", colors.green)
    end
  end

  doLaunch = function()
    local it = items()[sel[tab]]
    if it then system.launch(it.id) end
  end

  doUpdate = function()
    local it = items()[sel[tab]]
    if not it then return end
    local ref = system.getSource(it.id)
    local m = ref and { source = ref, name = it.name, author = it.author, description = it.description } or nil
    if not m or not m.source then setStatus("Source inconnue : mise a jour impossible.", colors.red) return end
    setStatus("Mise a jour de " .. it.name .. "...", colors.gray); render()
    local ok, res = installApp(it.id, { name = m.name or it.name, author = m.author, description = m.description }, m.source)
    if ok then setStatus(it.name .. " mis a jour.", colors.green) else setStatus(tostring(res), colors.red) end
  end

  doLink = function()
    local link = trim(ask("Lien ou code :"))
    if link == "" then return end
    local url, kind, ref = resolveSource(link)
    if not url then setStatus("Lien invalide.", colors.red) return end
    local guess = ref:match("([^/]+)%.as$") or ((kind == "pastebin") and ref) or ref:match("([^/]+)/?$") or "app"
    local name = trim(ask("Nom de l'app :", guess))
    if name == "" then name = guess end
    local id = sanitizeId(name)
    setStatus("Telechargement...", colors.gray); render()
    local ok, res = installApp(id, { name = name, author = "inconnu", description = "Installee depuis un lien" }, ref)
    if ok then setStatus(name .. " installe : " .. res, colors.green) else setStatus(tostring(res), colors.red) end
  end

  loadRegistry()
  while true do
    render()
    local e, a, b, c = os.pullEvent()
    local _, _, listTop, listRows = geom()
    if e == "mouse_click" then
      local handled = false
      for _, bt in ipairs(btns) do
        if c == bt[3] and b >= bt[1] and b <= bt[2] then bt[4](); handled = true; break end
      end
      if not handled and tab ~= 2 and c >= listTop and c < listTop + listRows then
        local idx = scroll[tab] + (c - listTop) + 1
        if items()[idx] then sel[tab] = idx end
      end
    elseif e == "mouse_scroll" and tab ~= 2 then
      local n = #items()
      scroll[tab] = math.max(0, math.min(math.max(0, n - listRows), scroll[tab] + a))
      sel[tab] = math.max(1, math.min(n, math.max(scroll[tab] + 1, math.min(sel[tab], scroll[tab] + listRows))))
    elseif e == "key" and tab ~= 2 then
      if a == keys.up then sel[tab] = math.max(1, sel[tab] - 1)
      elseif a == keys.down then sel[tab] = math.max(1, math.min(#items(), sel[tab] + 1))
      elseif a == keys.enter then if tab == 1 then doInstall() else doLaunch() end end
    end
  end
end


runStore()
