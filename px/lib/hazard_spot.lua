-- A random place on the ground for a hazard, where a 50 by 50 box above it is clear.

local spot = {}

local STEP = 5 -- pixels between the columns scanned
local HALF, BOX = 25, 50 -- the box: x - 25 .. x + 24 and y - 49 .. y, its bottom row y
local WORM_GAP, HAZARD_GAP = 75, 100 -- pixels from the box's centre to a worm and to another hazard
local BODIES = { "terrain", "worms", "crates", "oil", "mines", "graves", "missiles", "actors" }

-- Every ground point above the water, top to bottom in each column: the last free row above land.
function spot.ground()
  local size = wa.world.size()
  local water = wa.world.water()
  local out = {}
  for x = HALF, size.w - HALF, STEP do
    local y = 0
    while y < water do
      -- one that starts in land comes free first, so each trace finds the next surface down
      local hit = wa.world.trace({ x0 = x, y0 = y, x1 = x, y1 = water, with = { "terrain" } })
      if not hit or not hit.hit then break end
      local g = math.floor(hit.y)
      if g >= BOX - 1 and g + 2 < water then out[#out + 1] = { x, g } end
      y = g + 1
    end
  end
  return out
end

-- The square root of n, rounded down, in integers (the same on every machine).
local function isqrt(n)
  local x, y = n, (n + 1) // 2
  while y < x do x, y = y, (y + n // y) // 2 end
  return x
end

-- How many hazards a density from 0 to 100 places on this map: at 100, one for every 75 pixels of
-- its mean side, the square root of width x height, so a map twice as wide and twice as tall gets
-- twice as many. The ground they stand on doesn't count: a rope race map's long flat floors would
-- give it several times what its size asks for, a battle map's slopes next to none.
function spot.count(density)
  local size = wa.world.size()
  return (density * isqrt(size.w * size.h) + 3750) // 7500
end

local function far(x, y, points, gap)
  for _, p in ipairs(points) do
    local dx, dy = p[1] - x, p[2] - y
    if dx * dx + dy * dy < gap * gap then return false end
  end
  return true
end

-- Whether the box over the ground point x, g meets land or a body.
local function box_clear(x, g)
  if wa.world.collides({ x = x, y = g - HALF, radius = HALF - 1, with = BODIES }) then return false end
  for row = g - BOX + 1, g do
    if wa.land.trace(x - HALF + 0.5, row + 0.5, x + HALF - 0.5, row + 0.5) then return false end
  end
  return true
end

-- The ground point x, y for the next hazard, scanned from a random one, or nil when none fits.
-- `taken` holds the hazards placed so far; the one found is added to it.
function spot.find(ground, taken)
  local n = #ground
  if n == 0 then return nil end
  local worms = {}
  for _, w in ipairs(wa.worms.all()) do
    if w.hp > 0 then worms[#worms + 1] = { w.x, w.y } end
  end
  local first = wa.random(1, n)
  for i = 0, n - 1 do
    local p = ground[(first - 1 + i) % n + 1]
    local x, g = p[1], p[2]
    local cy = g - HALF
    if far(x, cy, worms, WORM_GAP) and far(x, cy, taken, HAZARD_GAP) and box_clear(x, g) then
      taken[#taken + 1] = { x, cy }
      return x, g
    end
  end
  return nil
end

return spot
