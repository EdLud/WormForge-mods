-- A random free place for a crate, as Project X's crate scripts find one:
-- a 5-pixel grid scanned from a random cell, the first cell where a crate
-- fits and has land at most 1000 pixels below.

local spot = {}

local STEP, BELOW = 5, 1000
-- WA's crate is 24 by 29 pixels (its own drop's picker, 0x53F630, keeps that
-- box clear): a circle of its half width swept this far up and down. A crate
-- given less room sticks in the land it overlaps and hangs there.
local RADIUS, REACH = 12, 2.5
local BLOCKS = { "terrain", "worms", "crates", "oil", "mines" }

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
    if y + REACH < water
      and not wa.world.trace({ x0 = x, y0 = y - REACH, x1 = x, y1 = y + REACH, radius = RADIUS, with = BLOCKS }) then
      local hit = wa.world.trace({ x0 = x, y0 = y + REACH, x1 = x, y1 = y + BELOW, radius = RADIUS, with = { "terrain" } })
      if hit and hit.hit and hit.y < water then return x, y end
    end
  end
  return nil
end

return spot
