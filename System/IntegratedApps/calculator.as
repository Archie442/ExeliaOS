--@name Calcul
--@icon +-
--@color orange
--@textcolor white
--@size 24x13
--@author Exelia
--@description Calculatrice.
-- Calculatrice - application integree d'Exelia OS (ExeliaScript)
app = exelia.getProgram(app)
app.version = "1.0.0"
app.minOsVersion = 4.0
display = app.getObject(display)
local function appCalc()
  local expr, result = "", ""
  local grid = {
    { "C", "(", ")", "/" }, { "7", "8", "9", "*" }, { "4", "5", "6", "-" },
    { "1", "2", "3", "+" }, { "0", ".", "<", "=" },
  }
  local function evaluate()
    if expr == "" then return end
    local f = load("return " .. expr, "=calc", "t", {})
    local ok, r
    if f then ok, r = pcall(f) end
    if ok and type(r) == "number" and r == r and r ~= math.huge and r ~= -math.huge then
      result = tostring(r); expr = result
    else
      result = "Erreur"
    end
  end
  local function press(k)
    if k == "C" then expr, result = "", ""
    elseif k == "<" then expr = expr:sub(1, -2)
    elseif k == "=" then evaluate()
    else
      if result == "Erreur" then result = "" end
      expr = expr .. k
    end
  end
  while true do
    local w, h = term.getSize()
    local bw, bh = math.max(3, math.floor(w / 4)), 2
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white); term.clear()
    term.setCursorPos(1, 1); term.setBackgroundColor(colors.gray); term.clearLine()
    term.setCursorPos(math.max(1, w - #expr), 1); term.write(expr:sub(-w))
    term.setCursorPos(1, 2); term.clearLine()
    term.setTextColor(colors.yellow)
    term.setCursorPos(math.max(1, w - #result), 2); term.write(result:sub(-w))
    for r, row in ipairs(grid) do
      for c, k in ipairs(row) do
        local bg = colors.lightGray
        if k == "=" then bg = colors.green
        elseif k == "C" then bg = colors.red
        elseif k:match("[%+%-%*/]") then bg = colors.orange end
        local x, y = (c - 1) * bw + 1, 3 + (r - 1) * bh
        term.setBackgroundColor(bg); term.setTextColor(colors.black)
        for j = 0, bh - 1 do term.setCursorPos(x, y + j); term.write(string.rep(" ", bw - 1)) end
        term.setCursorPos(x + math.floor((bw - 2) / 2), y); term.write(k)
      end
    end
    local e, a, b, c = os.pullEvent()
    if e == "char" then
      if ("0123456789+-*/.()^%"):find(a, 1, true) then press(a)
      elseif a == "=" then press("=")
      elseif a == "c" or a == "C" then press("C") end
    elseif e == "key" then
      if a == keys.enter or a == keys.numPadEnter then press("=")
      elseif a == keys.backspace then press("<")
      elseif a == keys.delete then press("C") end
    elseif e == "mouse_click" then
      local col, row = math.floor((b - 1) / bw) + 1, math.floor((c - 3) / bh) + 1
      if grid[row] and grid[row][col] then press(grid[row][col]) end
    end
  end
end


appCalc()
