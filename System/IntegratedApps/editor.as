--@name Editeur
--@icon Ed
--@color white
--@textcolor black
--@size 52x17
--@author Exelia
--@description Editeur de texte avec coloration syntaxique.
-- Editeur - application integree d'Exelia OS (ExeliaScript)
app = exelia.getProgram(app)
app.version = "1.0.0"
app.minOsVersion = 4.0
display = app.getObject(display)
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

local kw = {}
for word in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%a+") do kw[word] = true end

local function colorize(line)
  local fg, n = {}, #line
  for i = 1, n do fg[i] = "0" end
  local i = 1
  while i <= n do
    local c = line:sub(i, i)
    if line:sub(i, i + 1) == "--" then
      for j = i, n do fg[j] = "d" end
      break
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n and line:sub(j, j) ~= c do
        if line:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      for k = i, math.min(j, n) do fg[k] = "1" end
      i = j + 1
    elseif c:match("[%a_]") then
      local word = line:match("^[%w_]+", i)
      if kw[word] then for k = i, i + #word - 1 do fg[k] = "3" end end
      i = i + #word
    elseif c:match("%d") then
      local num = line:match("^[%d%.]+", i)
      for k = i, i + #num - 1 do fg[k] = "4" end
      i = i + #num
    else
      i = i + 1
    end
  end
  return table.concat(fg)
end

local function runEditor(path)
  local lines = { "" }
  if path and fs.exists(path) and not fs.isDir(path) then
    local f = fs.open(path, "r")
    if f then
      lines = {}
      local l = f.readLine()
      while l do lines[#lines + 1] = l; l = f.readLine() end
      f.close()
      if #lines == 0 then lines = { "" } end
    end
  end
  local cx, cy, sx, sy = 1, 1, 0, 0
  local dirty, ctrl, status, quitArm = false, false, "", false
  local isLua = path and (path:match("%.lua$") or path:match("%.as$")) ~= nil

  local function geom()
    local w, h = term.getSize()
    local lnw = #tostring(#lines) + 1
    return w, h, lnw, h - 2, w - lnw
  end
  local function follow()
    local w, h, lnw, th, tw = geom()
    if cy - 1 < sy then sy = cy - 1 end
    if cy > sy + th then sy = cy - th end
    if cx - 1 < sx then sx = cx - 1 end
    if cx > sx + tw then sx = cx - tw end
    if sx < 0 then sx = 0 end
    if sy < 0 then sy = 0 end
  end
  local function render()
    local w, h, lnw, th, tw = geom()
    term.setCursorBlink(false)
    term.setBackgroundColor(colors.gray); term.setTextColor(colors.white)
    term.setCursorPos(1, 1); term.clearLine()
    term.write((" " .. (path or "[sans nom]") .. (dirty and " *" or "")):sub(1, math.max(1, w - 14)))
    if w >= 20 then
      term.setCursorPos(w - 13, 1)
      term.setBackgroundColor(colors.green); term.write("[Sauver]")
      term.setBackgroundColor(colors.red); term.write("[Quit]")
    end
    for i = 1, th do
      local ln = sy + i
      term.setCursorPos(1, i + 1)
      term.setBackgroundColor(colors.black)
      if lines[ln] then
        term.setTextColor(colors.gray)
        term.write(string.format("%" .. (lnw - 1) .. "d ", ln))
        local s = lines[ln]
        local seg = s:sub(sx + 1, sx + tw)
        seg = seg .. string.rep(" ", tw - #seg)
        local f
        if isLua then f = colorize(s):sub(sx + 1, sx + tw) else f = string.rep("0", #s):sub(sx + 1, sx + tw) end
        f = f .. string.rep("0", tw - #f)
        term.blit(seg, f, string.rep("f", tw))
      else
        term.clearLine()
      end
    end
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray); term.setTextColor(colors.white); term.clearLine()
    term.write((" Ln " .. cy .. " Col " .. cx .. "  ^S sauver ^Q quitter  " .. status):sub(1, w))
    term.setCursorPos(lnw + cx - sx, cy - sy + 1)
    term.setTextColor(colors.white)
    term.setCursorBlink(true)
  end
  local function insertText(s)
    local line = lines[cy]
    local before, after = line:sub(1, cx - 1), line:sub(cx)
    local parts = {}
    for part in (s .. "\n"):gmatch("(.-)\r?\n") do parts[#parts + 1] = part end
    if #parts == 1 then
      lines[cy] = before .. parts[1] .. after
      cx = cx + #parts[1]
    else
      lines[cy] = before .. parts[1]
      for i = 2, #parts - 1 do table.insert(lines, cy + i - 1, parts[i]) end
      table.insert(lines, cy + #parts - 1, parts[#parts] .. after)
      cy = cy + #parts - 1
      cx = #parts[#parts] + 1
    end
    dirty = true
  end
  local function save()
    if not path then
      local n = ask("Enregistrer sous:")
      if n == "" then status = "Annule"; return end
      path = fs.combine("", n)
      isLua = (path:match("%.lua$") or path:match("%.as$")) ~= nil
    end
    local ok = pcall(function()
      local f = fs.open(path, "w")
      f.write(table.concat(lines, "\n"))
      f.close()
    end)
    if ok then dirty = false; status = "Enregistre." else status = "Echec (lecture seule ?)" end
  end

  while true do
    follow()
    render()
    local e, a, b, c = os.pullEvent()
    local _, h, _, th = geom()
    if e == "char" then
      ctrl = false; quitArm = false; status = ""
      insertText(a)
    elseif e == "paste" then
      insertText(a)
    elseif e == "key_up" then
      if a == keys.leftCtrl or a == keys.rightCtrl then ctrl = false end
    elseif e == "key" then
      local line = lines[cy]
      if a == keys.leftCtrl or a == keys.rightCtrl then ctrl = true
      elseif ctrl and a == keys.s then save()
      elseif ctrl and a == keys.q then
        if dirty and not quitArm then status = "Modifie ! ^Q encore pour quitter"; quitArm = true
        else return end
      elseif a == keys.left then
        if cx > 1 then cx = cx - 1 elseif cy > 1 then cy = cy - 1; cx = #lines[cy] + 1 end
      elseif a == keys.right then
        if cx <= #line then cx = cx + 1 elseif cy < #lines then cy = cy + 1; cx = 1 end
      elseif a == keys.up then
        if cy > 1 then cy = cy - 1; cx = math.min(cx, #lines[cy] + 1) end
      elseif a == keys.down then
        if cy < #lines then cy = cy + 1; cx = math.min(cx, #lines[cy] + 1) end
      elseif a == keys.home then cx = 1
      elseif a == keys["end"] then cx = #line + 1
      elseif a == keys.pageUp then cy = math.max(1, cy - th); cx = math.min(cx, #lines[cy] + 1)
      elseif a == keys.pageDown then cy = math.min(#lines, cy + th); cx = math.min(cx, #lines[cy] + 1)
      elseif a == keys.enter then
        insertText("\n" .. line:sub(1, cx - 1):match("^%s*"))
      elseif a == keys.tab then insertText("  ")
      elseif a == keys.backspace then
        if cx > 1 then
          lines[cy] = line:sub(1, cx - 2) .. line:sub(cx); cx = cx - 1; dirty = true
        elseif cy > 1 then
          local prev = lines[cy - 1]
          cx = #prev + 1; lines[cy - 1] = prev .. line
          table.remove(lines, cy); cy = cy - 1; dirty = true
        end
      elseif a == keys.delete then
        if cx <= #line then lines[cy] = line:sub(1, cx - 1) .. line:sub(cx + 1); dirty = true
        elseif cy < #lines then lines[cy] = line .. lines[cy + 1]; table.remove(lines, cy + 1); dirty = true end
      end
    elseif e == "mouse_click" then
      local w, _, lnw = geom()
      if c == 1 then
        if b >= w - 13 and b <= w - 6 then save()
        elseif b >= w - 5 and b <= w then
          if dirty and not quitArm then status = "Modifie ! Quit encore pour quitter"; quitArm = true
          else return end
        end
      elseif c >= 2 and c <= h - 1 then
        cy = math.max(1, math.min(#lines, sy + c - 1))
        cx = math.max(1, math.min(#lines[cy] + 1, sx + b - lnw))
      end
    elseif e == "mouse_scroll" then
      sy = math.max(0, math.min(math.max(0, #lines - th), sy + a))
      -- garder le curseur visible
      if cy <= sy then cy = sy + 1 end
      if cy > sy + th then cy = sy + th end
      cx = math.min(cx, #lines[cy] + 1)
    end
  end
end


local args = { ... }
local target = args[1]
display.window().name = target and ("Editeur - " + fs.getName(target)) or "Editeur"
runEditor(target)
