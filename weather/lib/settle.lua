-- Settling snow: a pixel at a time on the land, sliding off steep steps, falling when its land goes, melting.
local snow = require("lib/snow")

local settle = {}

settle.SHEET = "sprites/settle.png"
local FRAME = 9 -- pixels, the square frames of the sheet; each draws on the middle column, from the bottom row up
settle.SHADES = 4 -- frames 0..3: one pixel of snow, in four shades
settle.STRIP = 4 -- frame STRIP + h - 1: a column of h pixels of snow, h 1..FRAME
local TICK = 5 -- frames between tries
local WIDTH_PER_TRY = 250 -- pixels of map width a try a tick stands for, at full snow
local STAMPS = 8 -- pixels of snow laid a tick at most
local CLEAR = 14 -- pixels kept free round worms and objects
local SLIDE = 3 -- a pixel of snow slides to the next column when that is this much lower or more
local SLIDES = 64 -- columns a pixel slides across at most
local LEVEL = 6 -- columns a pixel moves across at most onto thinner snow
local REACH = 2 -- pixels up or down the next column's top may lie for snow to spread onto it
local LEDGE = 2 -- pixels of snow a column holds on a steep face
local CLIMB = 16 -- pixels up through the land a flake looks for its top
local LEAN = 0.7 -- most a settling flake's path slants in the wind, pixels across a pixel fallen
local CHECKS = 24 -- snowy columns checked a frame for land taken from under them
local NEAR = 3 -- columns either side checked at once after one changes
local MELT_CUTS = 40 -- melting cuts a frame at most
local BLEND = 0.3 -- how much of the colour of the ground under it settled snow takes

-- The centre of a frame of the sheet whose bottom row lies on row `bottom` of column x.
function settle.centre(x, bottom)
  return x, bottom - (FRAME - 1) + FRAME // 2
end

-- The pixels frame f draws, as offsets from its centre.
function settle.frame_pixels(f)
  local h = f < settle.SHADES and 1 or f - settle.STRIP + 1
  local out = {}
  for k = 0, h - 1 do out[k + 1] = { 0, FRAME // 2 - k } end
  return out
end

-- The snow of a match: by column, the top pixel of its snow and how deep it is; the columns in the order they
-- first had snow; the columns to check first; the cuts waiting to melt.
function settle.new_state()
  return { cols = {}, order = {}, sweep = 1, urgent = {}, marked = {}, queue = {}, head = 1, due = 0 }
end

-- The first land at or below (x, y), down to the water; nil over the water.
local function land_below(x, y, water)
  local hit = wa.land.trace(x, y, x, water)
  return hit and math.floor(hit.y)
end

-- The top of the land a flake meets at (x, y): it falls to the land below, or climbs to the top of the land it hit.
local function surface(x, y, water)
  local s = land_below(x, y, water)
  if not s then return nil end
  for _ = 1, CLIMB do
    if not wa.land.solid(x, s - 1) then return s end
    s = s - 1
  end
  return nil
end

-- Where a pixel of snow landing on top of column x (land at s) comes to rest: on the next column while that is
-- at least SLIDE lower, the steeper side first; nil when it slides into the water.
local function slide(x, s, width, water)
  for _ = 1, SLIDES do
    local drop, bx, bs = SLIDE - 1, nil, nil
    for _, dx in ipairs({ -1, 1 }) do
      local nx = x + dx
      if nx >= 0 and nx < width and not wa.land.solid(nx, s - 1) then
        local ns = land_below(nx, s - 1, water)
        local d = ns and ns - s or math.huge
        -- A tie goes one way or the other by where it is, the same on every machine.
        if d > drop or (d == drop and bx and (x + s) % 2 == 1) then drop, bx, bs = d, nx, ns end
      end
    end
    if not bx then return x, s end
    if not bs then return nil end
    x, s = bx, bs
  end
  return x, s
end

-- The top of the land in column x within REACH pixels up or down of row s, or nil: a wall or a drop past it.
local function beside(x, s)
  local solid = wa.land.solid
  if solid(x, s) then
    for y = s - 1, s - REACH, -1 do
      if not solid(x, y) then return y + 1 end
    end
    return nil
  end
  for y = s + 1, s + REACH do
    if solid(x, y) then return y end
  end
  return nil
end

-- Where a pixel of snow resting on column x (land at s) settles: on the next column where the snow's depth plus how
-- high its top stands is least, never up a steep step of the land. Thinner snow and dips draw it, so it lies along
-- the land's shape, smoothing its smallest bumps by half without levelling into terraces.
local function level(cols, x, s, width)
  -- The land under a column's snow: where it lies on the ground.
  local function ground(c, top)
    local col = cols[c]
    return (col and col.depth > 0) and col.top + col.depth or top
  end
  for _ = 1, LEVEL do
    local gx = ground(x, s)
    -- Rows count down the screen: a top standing higher has a smaller row, so a larger score.
    local best, low = (cols[x] and cols[x].depth or 0) - s, s
    local bx, bs
    for _, dx in ipairs({ -1, 1 }) do
      local nx = x + dx
      local ns = nx >= 0 and nx < width and beside(nx, s)
      -- Down any step of the land, but never up one SLIDE high or more: steep faces stay bare.
      if ns and gx - ground(nx, ns) < SLIDE then
        local score = (cols[nx] and cols[nx].depth or 0) - ns
        -- An equal score goes to the lower top; two alike go one way or the other by where they are,
        -- the same on every machine.
        if score < best or (score == best and (ns > low or (bx and ns == low and (x + s) % 2 == 1))) then
          best, low, bx, bs = score, ns, nx, ns
        end
      end
    end
    if not bx then return x, s end
    x, s = bx, bs
  end
  return x, s
end

-- Whether column x stands on a steep face: the ground of both next columns SLIDE pixels or more from its own (at g).
local function steep(cols, x, g, width)
  local solid = wa.land.solid
  for _, nx in ipairs({ x - 1, x + 1 }) do
    if nx >= 0 and nx < width then
      local col = cols[nx]
      local near
      if col and col.depth > 0 then
        near = math.abs(col.top + col.depth - g) < SLIDE
      else
        near = not solid(nx, g - SLIDE) and solid(nx, g + SLIDE - 1)
      end
      if near then return false end
    end
  end
  return true
end

-- Whether a pixel of snow on row t of column x would stand 2 pixels or more over the tops of both next columns:
-- snow doesn't rest there, it slides off. Piles never rise into pillars over what is round them.
local function spire(x, t, width)
  local solid = wa.land.solid
  for _, nx in ipairs({ x - 1, x + 1 }) do
    if nx < 0 or nx >= width or solid(nx, t) or solid(nx, t + 1) then return false end
  end
  return true
end

local function crowded(x, y)
  local near = { near = { x, y, CLEAR } }
  for _, list in ipairs({ wa.worms, wa.mines, wa.oil, wa.crates, wa.graves, wa.actors }) do
    if list and list.all and #list.all(near) > 0 then return true end
  end
  return false
end

-- Columns of strips covering rows y0..y1 of column x, the lowest first: each(frame, x, bottom row).
local function strips(x, y0, y1, each)
  local bottom = y1
  while bottom >= y0 do
    local h = math.min(FRAME, bottom - y0 + 1)
    each(settle.STRIP + h - 1, x, bottom)
    bottom = bottom - h
  end
end

local function stamp(f, x, bottom)
  local cx, cy = settle.centre(x, bottom)
  wa.land.stamp({ sprite = settle.SHEET, frame = f, x = cx, y = cy, true_colour = { blend = BLEND } })
end

local function cut(f, x, bottom)
  local cx, cy = settle.centre(x, bottom)
  wa.land.cut({ x = cx, y = cy, shape = "sprite", sprite = settle.SHEET, frame = f })
end

local function mark(s, x)
  if s.cols[x] and not s.marked[x] then
    s.marked[x] = true
    s.urgent[#s.urgent + 1] = x
  end
end

-- Column x as the land has it now: snow cut away is forgotten, snow cut from the top is shorter, and snow with
-- no land under it, or with a hole cut through it, falls onto the land below. True when it fell.
function settle.check(s, x, water)
  local col = s.cols[x]
  if not col or col.depth == 0 then return false end
  local base = col.top + col.depth
  -- Its top, middle and the land under it still there: as it was, without reading every pixel.
  local solid = wa.land.solid
  if solid(x, base) and solid(x, col.top) and solid(x, col.top + col.depth // 2) then return false end
  local left, run, in_run = 0, 0, true
  for y = base - 1, col.top, -1 do
    if wa.land.solid(x, y) then
      left = left + 1
      if in_run then run = run + 1 end
    else
      in_run = false
    end
  end
  if left == 0 then
    col.depth = 0
    return false
  end
  if run == left and wa.land.solid(x, base) then
    col.top, col.depth = base - left, left
    return false
  end
  strips(x, col.top, base - 1, cut)
  col.depth = 0
  -- What is left falls and settles again a pixel at a time, as flakes do; a pixel that finds no place is lost.
  for _ = 1, left do
    local top = surface(x, base, water)
    if not (top and settle.place(s, x, top, water, false)) then break end
  end
  return true
end

-- One frame of checks: the columns next to a change first, then the next snowy columns in turn.
function settle.sweep(s, water)
  local n, head = 0, 1
  while n < CHECKS and head <= #s.urgent do
    local x = s.urgent[head]
    head, n = head + 1, n + 1
    s.marked[x] = nil
    if settle.check(s, x, water) then
      for d = 1, NEAR do mark(s, x - d); mark(s, x + d) end
    end
  end
  local rest = {}
  for i = head, #s.urgent do rest[#rest + 1] = s.urgent[i] end
  s.urgent = rest
  local count = #s.order
  while n < CHECKS and count > 0 do
    if s.sweep > count then s.sweep = 1 end
    local x = s.order[s.sweep]
    s.sweep, n = s.sweep + 1, n + 1
    if settle.check(s, x, water) then
      for d = 1, NEAR do mark(s, x - d); mark(s, x + d) end
    end
  end
end

-- One flake: where the wind brings it down on open ground, what it slides to, a pixel of snow there.
function settle.try(s, cfg, size)
  local x = wa.random(0, size.w - 1)
  local water = wa.world.water()
  s.slant = math.max(-LEAN, math.min(LEAN, snow.slant(wa.world.wind(), cfg)))
  local lean = s.slant * (water + 64)
  local hit = wa.land.trace(x - lean, -64, x, water)
  if not hit or hit.starts_solid then return false end
  local hx = math.floor(hit.x)
  if hx < 0 or hx >= size.w then return false end
  local top = surface(hx, math.floor(hit.y), water)
  if not top then return false end
  return settle.place(s, hx, top, water, true)
end

-- A pixel of snow come down on the land at the top (row `top`) of column x: where it slides and spreads to, and
-- whether it rests there. `reconcile` first brings that column's snow up to date with the land.
function settle.place(s, x, top, water, reconcile)
  local cfg, width = s.cfg, s.width
  local px, py = slide(x, top, width, water)
  if not px then return false end
  px, py = level(s.cols, px, py, width)
  if py < 2 or py > water - 2 then return false end
  if reconcile then settle.check(s, px, water) end
  local col = s.cols[px]
  -- Land laid over this snow since (a girder): the flake lands on that, which this column doesn't follow.
  if col and col.depth > 0 and col.top ~= py then return false end
  if col and col.depth >= cfg.settle_depth then return false end
  if col and col.depth >= LEDGE and steep(s.cols, px, col.top + col.depth, width) then return false end
  if spire(px, py - 1, width) then return false end
  -- Open to the sky the way the wind brings flakes: none settles under a ledge or in a cave.
  local up = py - 1 + 64
  if wa.land.trace(px, py - 1, px - (s.slant or 0) * up, -64) then return false end
  if crowded(px, py - 1) then return false end
  stamp(wa.random(0, settle.SHADES - 1), px, py - 1)
  if col then
    col.top, col.depth = py - 1, col.depth + 1
  else
    s.cols[px] = { top = py - 1, depth = 1 }
    s.order[#s.order + 1] = px
  end
  return true
end

-- The top `px` of the snow in every column, queued to melt.
function settle.melt(s, px)
  for _, x in ipairs(s.order) do
    local col = s.cols[x]
    if col.depth > 0 then
      local h = math.min(px, col.depth)
      strips(x, col.top, col.top + h - 1, function(f, cx, bottom)
        s.queue[#s.queue + 1] = { f = f, x = cx, bottom = bottom }
      end)
      col.top, col.depth = col.top + h, col.depth - h
    end
  end
end

-- The next melting cuts, as many as a frame takes.
function settle.drain(s)
  local n = 0
  while s.head <= #s.queue and n < MELT_CUTS do
    local c = s.queue[s.head]
    s.head = s.head + 1
    cut(c.f, c.x, c.bottom)
    n = n + 1
  end
  if s.head > #s.queue then s.queue, s.head = {}, 1 end
end

-- On the weather clock: snow settles while it snows and falls when its land goes; with the cycle it melts at
-- each turn cycle, twice as fast in rain.
function settle.install(W)
  local cfg = W.kinds.snow
  if not (cfg and cfg.settle and cfg.amount > 0) then return end
  local s = settle.new_state()
  settle.state = s
  s.cfg = cfg
  local size
  W.ticks[#W.ticks + 1] = function(frame)
    size = size or wa.world.size()
    s.width = size.w
    settle.drain(s)
    local water = wa.world.water()
    settle.sweep(s, water)
    if frame % TICK ~= 0 or W.target.snow == 0 then return end
    s.due = s.due + size.w * cfg.amount / WIDTH_PER_TRY
    local stamps = 0
    while s.due >= 1 do
      s.due = s.due - 1
      if stamps < STAMPS and settle.try(s, cfg, size) then stamps = stamps + 1 end
    end
  end
  W.on_cycle[#W.on_cycle + 1] = function()
    local melt = W.cycle_cfg and W.cycle_cfg.melt or 0
    if melt > 0 and W.target.snow == 0 then settle.melt(s, W.target.rain == 1 and 2 * melt or melt) end
  end
end

return settle
