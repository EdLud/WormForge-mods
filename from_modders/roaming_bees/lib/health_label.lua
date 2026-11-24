-- A bee's health over its head: small 5x7 digits, green at full health and
-- red when almost gone. Project X's sentry label (px's lib/sentry_health).

local M = { SHEET = "sprites/health/digits.png" }
local WIDTH, HEIGHT, ADVANCE = 5, 7, 6

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

local QUAD = { sprite = M.SHEET, blend = "alpha", points = { {}, {}, {}, {} } }

local function digit(frame, x, y, tint, depth)
  local p = QUAD.points
  p[1][1], p[1][2] = x, y
  p[2][1], p[2][2] = x + WIDTH, y
  p[3][1], p[3][2] = x + WIDTH, y + HEIGHT
  p[4][1], p[4][2] = x, y + HEIGHT
  QUAD.frame, QUAD.color, QUAD.depth = frame, tint, depth
  wa.draw.quad(QUAD)
end

-- `health` centred on x, its digits' bottom at `bottom`.
function M.draw(health, maximum, x, bottom, depth)
  local text = tostring(math.max(0, math.ceil(health)))
  local left = math.floor(x - (#text * ADVANCE - 1) / 2 + 0.5)
  local top = math.floor(bottom - HEIGHT - 1)
  local tint = colour(health, maximum)
  for i = 1, #text do
    local frame, dx = tonumber(text:sub(i, i)), left + (i - 1) * ADVANCE
    digit(frame, dx + 1, top + 1, 0x60000000, depth)
    digit(frame, dx, top, tint, depth)
  end
end

return M
