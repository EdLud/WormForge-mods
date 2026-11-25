-- A random free place for a crate, as Project X's crate scripts find one:
-- a 5-pixel grid scanned from a random cell, the first cell where a crate
-- fits and has land at most 1000 pixels below.

local spot = {}

local STEP, BELOW = 5, 1000
-- WA's crate box, as its own drop's picker (0x53F630) passes it: 24 by 29
-- pixels, 12 left of the crate's x and 19 above its y, so x - 12 .. x + 11
-- and y - 19 .. y + 9. WA's crate constructor lifts a crate whose box meets
-- the land 16 pixels at a time until it is clear (0x5025D0), which takes a
-- crate just under a cavern's ceiling out above the roof.
local LEFT, UP, DOWN = 12, 19, 9
local MID = (DOWN - UP) / 2 -- the box's centre row, from y
-- A circle of the box's half width swept to its top and bottom rows: one
-- trace that turns away most cells and keeps clear of the objects. Its
-- corners are then checked row by row.
local RADIUS, REACH = 12, (UP + DOWN + 1) / 2 - 12
local BLOCKS = { "terrain", "worms", "crates", "oil", "mines" }

-- Whether any row of the box at x, y has land, at pixel centres.
local function box_hits_land(x, y)
  for row = y - UP, y + DOWN do
    if wa.land.trace(x - LEFT + 0.5, row + 0.5, x + LEFT - 0.5, row + 0.5) then return true end
  end
  return false
end

-- x, y in pixels, or nil when no cell fits. Draws two numbers from
-- wa.random, so every peer finds the same place.
function spot.find()
  local size = wa.world.size()
  local cols, rows = size.w // STEP, size.h // STEP
  if cols < 1 or rows < 1 then return nil end
  local col0, row0 = wa.random(0, cols - 1), wa.random(0, rows - 1)
  local water = wa.world.water()
  for n = 0, cols * rows - 1 do
    local x = ((col0 + n % cols) % cols) * STEP
    local y = ((row0 + n // cols) % rows) * STEP
    local cy = y + MID
    if y - UP >= 0 and y + DOWN < water
      and not wa.world.trace({ x0 = x, y0 = cy - REACH, x1 = x, y1 = cy + REACH, radius = RADIUS, with = BLOCKS })
      and not box_hits_land(x, y) then
      local hit = wa.world.trace({ x0 = x, y0 = cy + REACH, x1 = x, y1 = cy + BELOW, radius = RADIUS, with = { "terrain" } })
      if hit and hit.hit and hit.y < water then return x, y end
    end
  end
  return nil
end

return spot
