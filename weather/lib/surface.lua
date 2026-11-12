-- Rain on the ground and the water: splashes, and rings that stop where the land rises.
local surface = {}

local COLUMN = 8 -- pixels a cached ground height covers
local KEEP = 50 -- frames a cached height lasts
local SPLASH_LIFE = 12 -- frames
local SPLASH_SIZE = 9 -- half the splash, pixels
local MAX_SPLASHES = 96
local MAX_RINGS = 24
local RING_LIFE = 40 -- frames
local WATER_RING = 26 -- largest radius, pixels
local PUDDLE_RING = 11
local ASPECT = 0.22 -- a ring's height over its width
local ARC_POINTS = 8

-- The part of a ring of radius `r` round `cx` between the bounds: its left and right x, or nil.
function surface.clip(cx, r, left, right)
  local a, b = math.max(left, cx - r), math.min(right, cx + r)
  if a >= b then return nil end
  return a, b
end

-- How far the open water or the flat ground reaches either side of x, up to `reach`.
function surface.bounds(x, reach, step, open)
  local far = reach - reach % step
  local left, right = x - far, x + far
  for d = step, far, step do
    if not open(x - d) then left = x - d + step; break end
  end
  for d = step, far, step do
    if not open(x + d) then right = x + d - step; break end
  end
  return left, right
end

function surface.install(cfg)
  if cfg.rain <= 0 then return nil end
  local splash_sheet = wa.sprites.key("sprites/splash.png")
  local ring_sheet = wa.sprites.key("sprites/ring.png")
  local oval_sheet = wa.sprites.key("sprites/oval.png")
  local over_water = wa.depth.FRONT - 1
  local on_ground = wa.depth.FRONT
  local heights = {}
  local splashes, rings = {}, {}
  local due, last = 0, nil
  local batches = {}
  for f = 0, 5 do
    batches[f] = { sprite = splash_sheet, frame = f, blend = "alpha", depth = on_ground, quads = {}, count = 0 }
  end
  local RIBBON = { sprite = ring_sheet, blend = "add", depth = over_water, points = {} }
  for i = 1, ARC_POINTS do RIBBON.points[i] = { x = 0, y = 0, width = 3, u = 0, color = 0 } end
  -- Whole rings go in one batch a depth; only a ring the shore cuts is drawn as arcs.
  local OVALS = {}
  for _, depth in ipairs({ over_water, on_ground }) do
    OVALS[depth] = { sprite = oval_sheet, frame = 0, blend = "add", depth = depth, quads = {}, count = 0 }
  end
  local OVAL_FILL = 0.84 -- the ellipse's extent within its sheet

  -- The first land under the sky at x, cached a second: its y, ROOF where the sky is closed, false over open water.
  local ROOF = "roof"
  local function ground(x, st)
    local col = x // COLUMN
    local c = heights[col]
    if c and st.now - c.at < KEEP then return c.y end
    local hit = wa.land.trace(x, -64, x, st.water)
    local y = false
    if hit then y = hit.starts_solid and ROOF or hit.y end
    heights[col] = { y = y, at = st.now }
    return y
  end

  local function add_ring(x, y, water, st)
    if not cfg.ripples or #rings >= MAX_RINGS then return end
    local reach = water and WATER_RING or PUDDLE_RING
    local open
    if water then
      open = function(px) return not wa.land.solid(px, y - 2) end
    else
      open = function(px)
        local g = ground(px, st)
        return type(g) == "number" and math.abs(g - y) <= 1
      end
      if not (open(x - 4) and open(x + 4)) then return end
    end
    local left, right = surface.bounds(x, math.ceil(reach / OVAL_FILL) + 3, 3, open)
    rings[#rings + 1] = { x = x, y = y, born = st.now, reach = reach, left = left, right = right,
      depth = water and over_water or on_ground }
  end

  local function spawn(st)
    local x = st.left + wa.draw.random() * st.w
    local y = ground(x, st)
    local water = false
    if y == ROOF then return end
    if not y then
      if st.water > st.bottom + 20 or st.water < st.top - 20 then return end
      y, water = st.water, true
    elseif y < st.top - 20 or y > st.bottom + 20 then
      return
    end
    if #splashes < MAX_SPLASHES then splashes[#splashes + 1] = { x = x, y = y, born = st.now } end
    if water or wa.draw.random() < 0.5 then add_ring(x, y, water, st) end
  end

  local function arc(r, top, x0, x1, cx, cy, color, depth)
    local pts = RIBBON.points
    for i = 1, ARC_POINTS do
      local x = x0 + (x1 - x0) * (i - 1) / (ARC_POINTS - 1)
      local dy = ASPECT * math.sqrt(math.max(0, r * r - (x - cx) * (x - cx)))
      local p = pts[i]
      p.x, p.y, p.u = x, top and cy - dy or cy + dy, (i - 1) / (ARC_POINTS - 1)
      p.color = color
    end
    RIBBON.depth = depth
    wa.draw.ribbon(RIBBON)
  end

  local ovals = {}
  local function oval(g, r, color)
    local b = OVALS[g.depth]
    local n = ovals[g.depth]
    local rx, ry = r / OVAL_FILL, r / OVAL_FILL * ASPECT
    local l = b.quads
    l[n + 1], l[n + 2], l[n + 3], l[n + 4] = g.x - rx, g.y - ry, g.x + rx, g.y - ry
    l[n + 5], l[n + 6], l[n + 7], l[n + 8] = g.x + rx, g.y + ry, g.x - rx, g.y + ry
    l[n + 9] = color
    ovals[g.depth] = n + 9
  end

  -- A ring and, where a bound stopped it, its faint reflection.
  local function draw_ring(g, r, alpha)
    local color = (math.floor(255 * alpha) << 24) | 0xC8DCFF
    local box = r / OVAL_FILL
    if g.left <= g.x - box and g.x + box <= g.right then return oval(g, r, color) end
    local faint = (math.floor(255 * alpha * 0.35) << 24) | 0xC8DCFF
    for _, top in ipairs({ true, false }) do
      local a, b = surface.clip(g.x, r, g.left, g.right)
      if a then arc(r, top, a, b, g.x, g.y, color, g.depth) end
      if g.x + r > g.right then
        local m = 2 * g.right - g.x
        a, b = surface.clip(m, r, g.left, g.right)
        if a then arc(r, top, a, b, m, g.y, faint, g.depth) end
      end
      if g.x - r < g.left then
        local m = 2 * g.left - g.x
        a, b = surface.clip(m, r, g.left, g.right)
        if a then arc(r, top, a, b, m, g.y, faint, g.depth) end
      end
    end
  end

  -- Splashes a frame of the world: one for every 400 pixels of view at full rain.
  local rate = cfg.rain * 0.6
  return function(st)
    local step = last and st.now - last or 0
    if step < 0 or step > 50 then step = 0 end
    last = st.now
    due = due + step * rate * st.w / 400
    while due >= 1 do
      due = due - 1
      spawn(st)
    end
    local counts = { [0] = 0, 0, 0, 0, 0, 0 }
    for i = #splashes, 1, -1 do
      local s = splashes[i]
      local age = st.now - s.born
      if age >= SPLASH_LIFE or age < 0 then
        table.remove(splashes, i)
      else
        local f = math.min(5, math.floor(age * 6 / SPLASH_LIFE))
        local b, n = batches[f], counts[f]
        local l, h = b.quads, SPLASH_SIZE
        l[n + 1], l[n + 2], l[n + 3], l[n + 4] = s.x - h, s.y - 2 * h + 2, s.x + h, s.y - 2 * h + 2
        l[n + 5], l[n + 6], l[n + 7], l[n + 8] = s.x + h, s.y + 2, s.x - h, s.y + 2
        l[n + 9] = 0xB4FFFFFF
        counts[f] = n + 9
      end
    end
    for f = 0, 5 do
      if counts[f] > 0 then batches[f].count = counts[f] // 9; wa.draw.quads(batches[f]) end
    end
    ovals[over_water], ovals[on_ground] = 0, 0
    for i = #rings, 1, -1 do
      local g = rings[i]
      local t = (st.now - g.born) / RING_LIFE
      if t >= 1 or t < 0 then
        table.remove(rings, i)
      else
        local r = 2 + (g.reach - 2) * (1 - (1 - t) * (1 - t))
        draw_ring(g, r, 0.7 * (1 - t))
      end
    end
    for depth, n in pairs(ovals) do
      if n > 0 then OVALS[depth].count = n // 9; wa.draw.quads(OVALS[depth]) end
    end
  end
end

return surface
