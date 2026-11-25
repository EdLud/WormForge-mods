-- Settling snow: anywhere on the map, a pixel or a 2x2 square at a time, lying on the land or frosting it a little
-- way in; lying snow slides off steep steps, falls when its land goes and melts.
local settle = {}

settle.SHEET = "sprites/settle.png"
local FRAME = 9 -- pixels, the square frames of the sheet; each draws on the middle column, from the bottom row up
settle.SHADES = 4 -- frames 0..3: one pixel of snow, in four shades
settle.STRIP = 4 -- frame STRIP + h - 1: a column of h pixels of snow, h 1..FRAME
settle.SQUARE = settle.STRIP + FRAME -- frames SQUARE..SQUARE + 3: a 2x2 square, in four shades
local TICK = 5 -- frames between tries
local WIDTH_PER_TRY = 250 -- pixels of map width a try a tick stands for, at full snow
local STAMPS = 8 -- falls of snow (a pixel or a 2x2 square) laid a tick at most
local CLEAR = 14 -- pixels kept free round worms and objects
local SLIDE = 3 -- a pixel of snow slides to the next column when that is this much lower or more
local SLIDES = 64 -- columns a pixel slides across at most
local LEVEL = 6 -- columns a pixel moves across at most onto thinner snow
local REACH = 2 -- pixels up or down the next column's top may lie for snow to spread onto it
local LEDGE = 2 -- pixels of snow a column holds on a steep face
settle.BIG = 50 -- % of the snow that comes as 2x2 squares, the rest as single pixels
settle.FROST_SHARE = 50 -- % of the snow that frosts the land rather than lying on it
settle.FROST = 10 -- pixels into the land frost reaches, more often near its top
local FROST_CHECKS = 16 -- frost spots checked a frame for their land blown away
settle.CHUNK = 128 -- pixels of map width the glow is kept for together
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
  if f >= settle.SQUARE then
    local b = FRAME // 2
    return { { 0, b }, { 1, b }, { 0, b - 1 }, { 1, b - 1 } }
  end
  local h = f < settle.SHADES and 1 or f - settle.STRIP + 1
  local out = {}
  for k = 0, h - 1 do out[k + 1] = { 0, FRAME // 2 - k } end
  return out
end

-- The snow of a match: by column, the top pixel of its lying snow and how deep it is; the columns in the order they
-- first had snow; the columns to check first; the cuts waiting to melt; the frost spots, in the order laid and by
-- chunk of the map; and each chunk's count of changes, for the glow to follow.
function settle.new_state()
  return { cols = {}, order = {}, sweep = 1, urgent = {}, marked = {}, queue = {}, head = 1, due = 0,
    frost = {}, frosted = {}, chunks = {}, fsweep = 1, changes = {} }
end

-- The glow over column x changes.
local function touch(s, x)
  local c = x // settle.CHUNK
  s.changes[c] = (s.changes[c] or 0) + 1
end

-- The first land at or below (x, y), down to the water; nil over the water. WA's trace can stop a pixel short of the
-- land: the row returned is always solid.
local function land_below(x, y, water)
  local hit = wa.land.trace(x, y, x, water)
  if not hit then return nil end
  local s = math.floor(hit.y)
  for _ = 1, 2 do
    if wa.land.solid(x, s) then return s end
    s = s + 1
  end
  return wa.land.solid(x, s) and s or nil
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
  touch(s, x)
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
  -- Land a cut can't take (indestructible) was never snow: the column is forgotten, nothing falls.
  if wa.land.solid(x, col.top) then return false end
  -- What is left falls and settles again a pixel at a time, as flakes do; a pixel that finds no place is lost.
  for _ = 1, left do
    local top = land_below(x, base, water)
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

-- One fall of snow: a spot anywhere in the air of the map, straight down onto the land under it, a pixel or a 2x2
-- square, lying there or frosting the land. Returns how many pixels it laid.
function settle.try(s, size)
  local water = wa.world.water()
  local x, y = wa.random(0, size.w - 2), wa.random(0, water - 1)
  local big = wa.random(1, 100) <= settle.BIG
  if wa.land.solid(x, y) then return 0 end
  if wa.random(1, 100) <= settle.FROST_SHARE then
    local top = land_below(x, y, water)
    return top and settle.frost(s, x, top, big) or 0
  end
  local laid = 0
  for dx = 0, big and 1 or 0 do
    for _ = 1, big and 2 or 1 do
      -- Each pixel looks for the top again: the one before may have raised it.
      local top = not wa.land.solid(x + dx, y) and land_below(x + dx, y, water)
      if top and settle.place(s, x + dx, top, water, true) then laid = laid + 1 end
    end
  end
  return laid
end

-- Whether the w x w square at (x, y) is all land, none of it lying snow.
local function bare_land(s, x, y, w)
  for dx = 0, w - 1 do
    local col = s.cols[x + dx]
    for dy = 0, w - 1 do
      if not wa.land.solid(x + dx, y + dy) or s.frosted[(y + dy) * 65536 + x + dx] then return false end
      if col and col.depth > 0 and y + dy >= col.top and y + dy < col.top + col.depth then return false end
    end
  end
  return true
end

-- Frost on the land whose top is row `top` of column x: under any snow lying there, up to FROST pixels in.
function settle.frost(s, x, top, big)
  local col = s.cols[x]
  local ground = (col and col.depth > 0 and col.top == top) and top + col.depth or top
  local r = wa.random(0, 99)
  local y = ground + (settle.FROST - (big and 1 or 0)) * r * r // 10000
  local w = big and 2 or 1
  if not bare_land(s, x, y, w) then
    if not big or not bare_land(s, x, y, 1) then return 0 end
    w = 1
  end
  local f = wa.random(0, settle.SHADES - 1) + (w == 2 and settle.SQUARE or 0)
  stamp(f, x, y + w - 1)
  local spot = { x = x, y = y, w = w }
  s.frost[#s.frost + 1] = spot
  local c = x // settle.CHUNK
  local chunk = s.chunks[c] or {}
  s.chunks[c] = chunk
  chunk[#chunk + 1] = spot
  for dx = 0, w - 1 do
    for dy = 0, w - 1 do s.frosted[(y + dy) * 65536 + x + dx] = true end
  end
  touch(s, x)
  return w * w
end

-- The next frost spots: one whose land was blown away is forgotten.
function settle.frost_sweep(s)
  for _ = 1, math.min(FROST_CHECKS, #s.frost) do
    if s.fsweep > #s.frost then s.fsweep = 1 end
    local spot = s.frost[s.fsweep]
    if wa.land.solid(spot.x, spot.y) then
      s.fsweep = s.fsweep + 1
    else
      s.frost[s.fsweep] = s.frost[#s.frost]
      s.frost[#s.frost] = nil
      local c = spot.x // settle.CHUNK
      local kept = {}
      for _, other in ipairs(s.chunks[c]) do if other ~= spot then kept[#kept + 1] = other end end
      s.chunks[c] = kept
      for dx = 0, spot.w - 1 do
        for dy = 0, spot.w - 1 do s.frosted[(spot.y + dy) * 65536 + spot.x + dx] = nil end
      end
      touch(s, spot.x)
    end
  end
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
  -- Only into the air: snow is never laid over land.
  if wa.land.solid(px, py - 1) then return false end
  if crowded(px, py - 1) then return false end
  stamp(wa.random(0, settle.SHADES - 1), px, py - 1)
  if col then
    col.top, col.depth = py - 1, col.depth + 1
  else
    s.cols[px] = { top = py - 1, depth = 1 }
    s.order[#s.order + 1] = px
  end
  touch(s, px)
  return true
end

-- The top pixel of the snow in `percent` % of the snowy columns, picked at random, queued to melt.
function settle.melt(s, percent)
  for _, x in ipairs(s.order) do
    local col = s.cols[x]
    if col.depth > 0 and wa.random(1, 100) <= percent then
      s.queue[#s.queue + 1] = { f = settle.STRIP, x = x, bottom = col.top }
      col.top, col.depth = col.top + 1, col.depth - 1
      touch(s, x)
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

-- On the weather clock: snow settles while it snows and lying snow falls when its land goes; it melts a little at the
-- start of each clear or rainy turn, twice as fast in rain. Frost stays.
function settle.install(W)
  local cfg = W.kinds.snow
  if not (cfg and cfg.amount > 0) then return end
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
    settle.frost_sweep(s)
    if frame % TICK ~= 0 or W.target.snow == 0 then return end
    s.due = s.due + size.w * cfg.amount / WIDTH_PER_TRY
    local falls = 0
    while s.due >= 1 do
      s.due = s.due - 1
      if falls < STAMPS and settle.try(s, size) > 0 then falls = falls + 1 end
    end
  end
  W.on_turn[#W.on_turn + 1] = function()
    local melt = W.cycle_cfg and W.cycle_cfg.melt or 0
    if melt > 0 and W.target.snow == 0 then settle.melt(s, math.min(100, W.target.rain == 1 and 2 * melt or melt)) end
  end
end

return settle
