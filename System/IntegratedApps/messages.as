--@name Messages
--@icon @
--@color cyan
--@textcolor black
--@size 44x15
--@author Exelia
--@description Messagerie entre ordinateurs (modem requis).
-- Messages - application integree d'Exelia OS (ExeliaScript)
app = exelia.getProgram(app)
app.version = "1.0.0"
app.minOsVersion = 4.0
display = app.getObject(display)
local function appChat()
  local opened = false
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "modem" then
      if not rednet.isOpen(n) then rednet.open(n) end
      opened = true
    end
  end
  local me = exelia.getUsername()
  if me == "" then me = os.getComputerLabel() or ("PC" .. os.getComputerID()) end
  local msgs, input = {}, ""
  local function add(s, c) msgs[#msgs + 1] = { s, c or colors.black } end
  add("Messagerie Exelia OS - ID " .. os.getComputerID(), colors.gray)
  if not opened then add("Aucun modem detecte !", colors.red) end
  while true do
    local w, h = term.getSize()
    term.setBackgroundColor(colors.white); term.setTextColor(colors.black); term.clear()
    term.setCursorPos(1, 1); term.setBackgroundColor(colors.cyan); term.clearLine()
    term.write(" Salon general  (" .. me .. ")")
    local rows = h - 2
    for i = 0, rows - 1 do
      local m = msgs[#msgs - rows + 1 + i]
      if m then
        term.setCursorPos(1, 2 + i); term.setBackgroundColor(colors.white)
        term.setTextColor(m[2]); term.write(m[1]:sub(1, w))
      end
    end
    term.setCursorPos(1, h); term.setBackgroundColor(colors.lightGray); term.setTextColor(colors.black)
    term.clearLine(); term.write(("> " .. input):sub(-w))
    local e, a, b, c = os.pullEvent()
    if e == "char" or e == "paste" then input = input .. a
    elseif e == "key" then
      if a == keys.backspace then input = input:sub(1, -2)
      elseif a == keys.enter and input ~= "" then
        if opened then rednet.broadcast(textutils.serialize({ n = me, t = input }), "exelia_chat") end
        add(me .. ": " .. input, colors.blue)
        input = ""
      end
    elseif e == "rednet_message" and c == "exelia_chat" then
      local d = textutils.unserialize(tostring(b))
      if type(d) == "table" then add(tostring(d.n) .. " (#" .. a .. "): " .. tostring(d.t), colors.black) end
    end
  end
end


appChat()
