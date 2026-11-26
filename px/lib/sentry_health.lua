-- Small 5x7 digits on a transparent sheet, with "." and the letters of "Dud".

local M = { SHEET = "sprites/sentry_ui/digits.png" }
local installed = false
local WIDTH, HEIGHT, ADVANCE = 5, 7, 6
local SHADOW = 0x60000000

function M.install()
  if installed then return end
  installed = true
  wa.assets.load({ sprites = { M.SHEET }, gpu_prefix = "sprites/sentry_ui/" })
end

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

local function digit(frame, x, y, tint, depth)
  wa.draw.quad({ sprite = M.SHEET, frame = frame, color = tint, depth = depth, blend = "alpha",
    points = { {x, y}, {x + WIDTH, y}, {x + WIDTH, y + HEIGHT}, {x, y + HEIGHT} } })
end

local GLYPH = { ["."] = 10, D = 11, u = 12, d = 13 }

-- `text` (digits, ".", "Dud") centred on x, above `bottom`, in `tint`.
function M.text(text, x, bottom, tint, depth)
  local left = math.floor(x - (#text * ADVANCE - 1) / 2 + 0.5)
  local top = math.floor(bottom - HEIGHT - 1)
  for i = 1, #text do
    local ch = text:sub(i, i)
    local frame, dx = tonumber(ch) or GLYPH[ch], left + (i - 1) * ADVANCE
    if frame then
      digit(frame, dx + 1, top + 1, 0x60000000, depth)
      digit(frame, dx, top, tint, depth)
    end
  end
end

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

-- Each colour and each number's digits, worked out once.
local tints = {}
local function tint_of(health, maximum)
  local by_health = tints[maximum]
  if not by_health then
    by_health = {}
    tints[maximum] = by_health
  end
  local c = by_health[health]
  if not c then
    c = colour(health, maximum)
    by_health[health] = c
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

-- M.draw's label into `batch` (lib/turret's `turret.batch` of M.SHEET), for many
-- labels a frame: no tables, drawn when the batch is.
function M.add(batch, health, maximum, x, bottom)
  local d = digits(math.max(0, math.ceil(health)))
  local left = math.floor(x - (#d * ADVANCE - 1) / 2 + 0.5)
  local top = math.floor(bottom - HEIGHT - 1)
  local c = tint_of(health, maximum)
  local cx, cy = WIDTH / 2, HEIGHT / 2
  for i = 1, #d do
    local dx = left + (i - 1) * ADVANCE
    batch:put(dx + 1 + cx, top + 1 + cy, WIDTH, HEIGHT, 0, d[i], SHADOW)
    batch:put(dx + cx, top + cy, WIDTH, HEIGHT, 0, d[i], c)
  end
end

return M
