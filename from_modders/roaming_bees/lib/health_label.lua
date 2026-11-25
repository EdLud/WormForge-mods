-- A bee's health over its head: small 5x7 digits, green at full health and
-- red when almost gone. Project X's sentry label (px's lib/sentry_health).
-- Inside wa.on.draw: start(depth), add(...) for each bee, finish(); every
-- label is one brush and one list of boxes, a box a digit and its shadow.

local M = { SHEET = "sprites/health/digits.png" }
local WIDTH, HEIGHT, ADVANCE = 5, 7, 6
local SHADOW = 0x60000000
local MAX_BOXES = 4096 -- brush:boxes' limit a call

local function colour(health, maximum)
  local ratio = math.max(0, math.min(1, health / maximum))
  local low, high, t
  if ratio <= 0.5 then
    low, high, t = { 240, 80, 64 }, { 240, 216, 80 }, ratio * 2
  else
    low, high, t = { 240, 216, 80 }, { 80, 240, 96 }, (ratio - 0.5) * 2
  end
  local r = math.floor(low[1] + (high[1] - low[1]) * t)
  local g = math.floor(low[2] + (high[2] - low[2]) * t)
  local b = math.floor(low[3] + (high[3] - low[3]) * t)
  return 0xB0000000 | (r << 16) | (g << 8) | b
end

-- Each colour and each number's digits, worked out once.
local tints = {}
local function tint(health, maximum)
  local byHealth = tints[maximum]
  if not byHealth then
    byHealth = {}
    tints[maximum] = byHealth
  end
  local c = byHealth[health]
  if not c then
    c = colour(health, maximum)
    byHealth[health] = c
  end
  return c
end

local numbers = {}
local function digits(n)
  local d = numbers[n]
  if not d then
    d = {}
    local text = tostring(n)
    for i = 1, #text do d[i] = tonumber(text:sub(i, i)) end
    numbers[n] = d
  end
  return d
end

local brushes = {}
local brush
local list, count = {}, 0

-- A 5x7 digit with its top left at (x, y).
local function box(x, y, frame, color)
  if count == MAX_BOXES then
    brush:boxes(list, count)
    count = 0
  end
  local i = count * 7
  list[i + 1], list[i + 2], list[i + 3], list[i + 4] = x + WIDTH / 2, y + HEIGHT / 2, WIDTH, HEIGHT
  list[i + 5], list[i + 6], list[i + 7] = 0, frame, color
  count = count + 1
end

function M.start(depth)
  brush = brushes[depth]
  if not brush then
    brush = wa.draw.brush{ sprite = M.SHEET, blend = "alpha", depth = depth }
    brushes[depth] = brush
  end
  count = 0
end

-- `health` centred on x, its digits' bottom at `bottom`.
function M.add(health, maximum, x, bottom)
  local d = digits(math.max(0, math.ceil(health)))
  local left = math.floor(x - (#d * ADVANCE - 1) / 2 + 0.5)
  local top = math.floor(bottom - HEIGHT - 1)
  local c = tint(health, maximum)
  for i = 1, #d do
    local dx = left + (i - 1) * ADVANCE
    box(dx + 1, top + 1, d[i], SHADOW)
    box(dx, top, d[i], c)
  end
end

function M.finish()
  if count > 0 then brush:boxes(list, count) end
  count = 0
end

return M
