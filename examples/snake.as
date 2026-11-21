-- ============================================================================
--  Snake  -  ecrit en ExeliaScript, le langage des applications d'Exelia OS
--  Fleches / ZQSD : diriger   Espace : pause / rejouer   P : pause
-- ============================================================================
app = exelia.getProgram(app)
app.version = "1.2.0"
app.minOsVersion = 4.0
app.pastebin = ""                       -- id Pastebin de cette app (mise a jour auto)
app.config.updating = "automatic"

display = app.getObject(display)
keyboard = app.getObject(keyboard)
mouse = app.getObject(mouse)
timer = app.getObject(timer)

display.window.on()
window = display.window()
window.name = "Snake " + app.version
window.resize(36, 17)

-- ---------------------------------------------------------------- etat --
-- groupe de donnees "scores" (fichier AppData/snake/scores.dg) : le record y est conserve
exelia.dataGroup.create("scores")
local best = 0
exelia.dataGroup.registerVariable("scores", best)   -- restaure le record sauvegarde
local snake, dir, nextDir, food
local score, dead, paused
local width, height
local tick

local function placeFood()
  while true do
    local fx = math.random(1, width)
    local fy = math.random(2, height)
    local free = true
    for _, part in ipairs(snake) do
      if part.x == fx and part.y == fy then
        free = false
        break
      end
    end
    if free then
      food = { x = fx, y = fy }
      return
    end
  end
end

local function reset()
  width = window.width
  height = window.height
  local sx = math.max(3, math.floor(width / 2))
  local sy = math.floor((height + 1) / 2) + 1
  snake = { { x = sx, y = sy }, { x = sx - 1, y = sy }, { x = sx - 2, y = sy } }
  dir = { 1, 0 }
  nextDir = { 1, 0 }
  score = 0
  dead = false
  paused = false
  placeFood()
  if tick then tick.setInterval(0.15) end
end

-- ------------------------------------------------------------- logique --
local function die()
  dead = true
  if score > best then
    best = score
    exelia.dataGroup.save(best, "scores")
    exelia.notifyUser("Snake", "Nouveau record : " + best + " point(s), bravo " + exelia.getUsername() + " !")
  end
end

local function step()
  dir = nextDir
  local head = snake[1]
  local nx = head.x + dir[1]
  local ny = head.y + dir[2]
  if nx < 1 or nx > width or ny < 2 or ny > height then
    die()
    return
  end
  for _, part in ipairs(snake) do
    if part.x == nx and part.y == ny then
      die()
      return
    end
  end
  table.insert(snake, 1, { x = nx, y = ny })
  if nx == food.x and ny == food.y then
    score = score + 1
    if score > best then best = score end
    tick.setInterval(math.max(0.05, 0.15 - score * 0.004))
    placeFood()
  else
    table.remove(snake)
  end
end

-- -------------------------------------------------------------- dessin --
local function draw()
  window.clear("black")
  window.rect(1, 1, width, 1, "gray")
  local status = "Score " + score + "   Record " + best
  if paused then status = status + "   PAUSE" end
  window.text(2, 1, status, "white", "gray")
  window.pixel(food.x, food.y, "red")
  for i, part in ipairs(snake) do
    if i == 1 then
      window.pixel(part.x, part.y, "green")
    else
      window.pixel(part.x, part.y, "lime")
    end
  end
  if dead then
    local middle = math.floor(height / 2)
    window.center(middle, "  GAME OVER  ", "white", "red")
    window.center(middle + 1, " Espace : rejouer ", "white", "gray")
  end
end

-- ----------------------------------------------------------- evenements --
keyboard.onKey(function(key)
  if (key == "up" or key == "w") and dir[2] == 0 then
    nextDir = { 0, -1 }
  elseif (key == "down" or key == "s") and dir[2] == 0 then
    nextDir = { 0, 1 }
  elseif (key == "left" or key == "a") and dir[1] == 0 then
    nextDir = { -1, 0 }
  elseif (key == "right" or key == "d") and dir[1] == 0 then
    nextDir = { 1, 0 }
  elseif key == "space" then
    if dead then reset() else paused = not paused end
  elseif key == "p" then
    paused = not paused
  end
  draw()
end)

mouse.onClick(function()
  if dead then
    reset()
    draw()
  end
end)

app.on("resize", function()
  reset()
  draw()
end)

exelia.notifyUser("Snake", "Bonne partie, " + exelia.getUsername() + " !")

reset()
draw()

tick = timer.every(0.15, function()
  if not dead and not paused then step() end
  draw()
end)
