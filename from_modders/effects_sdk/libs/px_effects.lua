-- PX's effect manager, as a shared module: reach arcs, the electric explosion
-- (ring + squashed lens), spark, glow, smoke and the round crater. The trail is
-- the effects SDK's `wf-lib/effects/trail`; this file only feeds it. PX
-- originals: wklua_and_px/utils/px_effects.c and effects_methods.c; the line
-- mapping is porting-analysis/electric_mine_effects.md.
--
-- Pure data at load: `wa` does not exist until `install(ctx)`. The trail is the
-- SDK's own export, so it resolves through the same bundle.
local trail = require("wf-lib/effects/trail")

local fx = {}

-- The effect manager's own art, exported by this bundle's asset namespace.
fx.SPARK = "wf-lib/effects/sprites/px_effects/spark"
fx.BLOB = "wf-lib/effects/sprites/px_effects/glow.png"
fx.SMOKE = "wf-lib/effects/sprites/px_effects/cloud.png"

-- The electric mine's numbers (weapon_electric_mine.c:20-25, :57, :70).
fx.PRESETS = {
  electric = {
    spark = { cell = 60, frames = 10, size = 0.4, rate = 0.02, pause = 0.1,
      r = 255, g = 255, b = 255 },
    glow = { cell = 128, size = 0.18, passes = 3, r = 20, g = 40, b = 70 },
    reach = { count = 2, first = { 6, 22 }, stagger = 12, cooldown = { 13, 51 },
      distance = 35, speed = { 0.08, 0.18 }, bulge = { -130, 130 },
      -- PX's own negative-bulge formula draws a detached arc; "arc" keeps the
      -- bolt on the mine and still bows at random.
      curve = "arc", terrain = true, noise = 4.0, segments = 16,
      core_w = 8.0, glow_w = 13.0, r = 130, g = 180, b = 255 },
    trail = { every = 2, max = 12, vanish = 2, core_w = 8.0, glow_w = 13.0,
      r = 130, g = 180, b = 255 },
    burst = { r = 100, g = 150, b = 220, noise = 1.1, duration = 18,
      fade = 0.55, grow = 3.0, live = 24,
      ellipse = { 1.25, 0.45 },
      rebuffer = { at = 16, noise = 1.8, r = 120, g = 170, b = 240,
        fade = -0.85, segments = 1.30 },
      smoke = { count = 7, kinds = 2, r = 100, g = 120, b = 190 } },
  },
}

local installed, settings, driver
local emitters, arcs, bursts, sparks, glows, smokes, rings = {}, {}, {}, {}, {}, {}, {}
local next_key = -1

local SPARK_KEYS = { "sprite", "cell", "frames", "size", "rate", "pause",
  "r", "g", "b", "depth" }
local GLOW_KEYS = { "sprite", "cell", "size", "passes", "r", "g", "b",
  "depth", "life" }
local REACH_KEYS = { "count", "first", "stagger", "cooldown", "distance",
  "speed", "bulge", "curve", "terrain", "noise", "segments", "core_w",
  "glow_w", "core_dome", "glow_dome", "r", "g", "b", "depth" }
local TRAIL_KEYS = { "every", "max", "vanish", "core_w", "glow_w", "r", "g",
  "b", "depth", "beam", "glow" }
local BURST_KEYS = { "r", "g", "b", "noise", "duration", "fade", "grow",
  "live", "segments", "thickness", "ellipse", "rebuffer", "smoke", "depth" }
local SMOKE_KEYS = { "count", "kinds", "r", "g", "b", "spread", "up", "life",
  "drag", "size", "depth", "sprite" }
local RING_KEYS = { "radius", "segments", "noise", "r", "g", "b", "depth",
  "speed", "angle", "core_w", "glow_w", "thin", "follow", "owner" }
local REBUFFER_KEYS = { "at", "noise", "r", "g", "b", "fade", "segments" }

local function merge(dst, src, keys)
  if not src then return dst end
  for _, k in ipairs(keys) do
    if src[k] ~= nil then dst[k] = src[k] end
  end
  return dst
end

local function copy(dst, src, keys)
  dst = dst or {}
  return merge(dst, src, keys)
end

local function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
  end
end

local function new_seed()
  return wa.random(1, 2147483646)
end

-- Park-Miller, exact in a double; one wa.random draw per effect seeds it.
local function next_rand(rng)
  rng.seed = (rng.seed * 48271) % 2147483647
  return rng.seed / 2147483647
end

local function rand_float(rng, a, b)
  if rng.random == "wa" then
    return a + (b - a) * (wa.random(0, 1000000) / 1000000)
  end
  return a + (b - a) * next_rand(rng)
end

local function rand_int(rng, a, b)
  if rng.random == "wa" then return wa.random(a, b) end
  return a + math.floor(next_rand(rng) * (b - a + 1))
end

local function new_rng(o)
  if o and o.rng then return o.rng end
  return { random = (o and o.random) or "lcg", seed = (o and o.seed) or new_seed() }
end

local function clamp01(v)
  if v < 0 then return 0 elseif v > 1 then return 1 end
  return v
end

local function wrap(a)
  while a > math.pi do a = a - 2 * math.pi end
  while a < -math.pi do a = a + 2 * math.pi end
  return a
end

-- Arc geometry: "px" is PX's sagitta formula verbatim (including its detached
-- negative-bulge arc); "arc" keeps the sign but always passes through both ends;
-- "line" and "bezier" are the other two PX curve types.
local function setup_arc(st)
  local dx, dy = st.to_x - st.from_x, st.to_y - st.from_y
  local dist = math.sqrt(dx * dx + dy * dy)
  st.dist = dist
  if dist <= 0.0001 then st.degenerate = true; return end
  local px, py = -dy / dist, dx / dist
  local mx, my = (st.from_x + st.to_x) * 0.5, (st.from_y + st.to_y) * 0.5
  st.mx, st.my, st.nx, st.ny = mx, my, px, py
  if st.curve == "line" then return end
  if st.curve == "bezier" then
    st.ctrl_x, st.ctrl_y = mx + px * st.bulge, my + py * st.bulge
    return
  end
  local chord = dist * 0.5
  local s = st.bulge
  local ux, uy = px, py
  if st.curve == "arc" and s < 0 then
    s, ux, uy = -s, -px, -py
  end
  if math.abs(s) < 0.001 then s = (s < 0) and -0.001 or 0.001 end
  local rad = (chord * chord + s * s) / (2 * s)
  local cx = mx - ux * (rad - s)
  local cy = my - uy * (rad - s)
  st.cx, st.cy, st.rad = cx, cy, rad
  st.a0 = wa.math.atan(st.from_y - cy, st.from_x - cx)
  st.a1 = wa.math.atan(st.to_y - cy, st.to_x - cx)
  st.da = wrap(st.a1 - st.a0)
end

local function arc_point(st, t)
  if st.degenerate then return st.from_x, st.from_y end
  if st.curve == "line" then
    return st.from_x + (st.to_x - st.from_x) * t,
      st.from_y + (st.to_y - st.from_y) * t
  end
  if st.curve == "bezier" then
    local u = 1 - t
    return u * u * st.from_x + 2 * u * t * st.ctrl_x + t * t * st.to_x,
      u * u * st.from_y + 2 * u * t * st.ctrl_y + t * t * st.to_y
  end
  local a = st.a0 + st.da * t
  return st.cx + st.rad * wa.math.cos(a), st.cy + st.rad * wa.math.sin(a)
end

local function fill_arc_noise(st)
  local n = st.segments + 1
  for i = 1, n do
    st.noise_vals[i] = rand_float(st.rng, -1, 1)
  end
  for i = n + 1, #st.noise_vals do st.noise_vals[i] = nil end
end

local function make_arc(o)
  local f, t = o.from or {}, o.to or {}
  local st = {
    from_x = o.from_x or f[1] or o.x0 or 0,
    from_y = o.from_y or f[2] or o.y0 or 0,
    to_x = o.to_x or t[1] or o.x1 or 0,
    to_y = o.to_y or t[2] or o.y1 or 0,
    curve = o.curve or "px", bulge = o.bulge or 0,
    speed = o.speed or 0.12, progress = 0,
    noise = o.noise or 4.0,
    segments = math.min(255, math.max(1, math.floor(o.segments or 16))),
    core_w = o.core_w or 8.0, glow_w = o.glow_w or 13.0,
    r = o.r or 130, g = o.g or 180, b = o.b or 255,
    depth = o.depth, persist = o.persist or false,
    on_done = o.on_done, done = false, owner = o.owner,
    rng = new_rng(o), noise_vals = {}, noise_age = 0,
  }
  st.core_dome = o.core_dome or st.core_w * 0.5
  st.glow_dome = o.glow_dome or st.glow_w * 0.5
  if st.curve ~= "line" and st.curve ~= "bezier" and st.curve ~= "arc" then
    st.curve = "px"
  end
  if o.terrain ~= false then
    local h = wa.land.trace(st.from_x, st.from_y, st.to_x, st.to_y)
    if h and h.hit then st.to_x, st.to_y = h.x, h.y end
  end
  setup_arc(st)
  fill_arc_noise(st)
  st.clear = function(self) self.done = true end
  return st
end

local function update_arc(st)
  if st.done then return end
  st.progress = st.progress + st.speed
  if st.progress >= 1 then
    st.progress, st.done = 1, true
    if st.on_done then st.on_done(st) end
  end
  st.noise_age = st.noise_age + 1
  if st.noise_age % 2 == 0 then fill_arc_noise(st) end
end

-- Drawing. One spec and one point pool, refilled per pass; wa.draw.ribbon
-- copies its table (the effects SDK trail does the same).
local RIBBON = { blend = "add", points = {} }
local POINTS = {}
for i = 1, 260 do POINTS[i] = { x = 0, y = 0, width = 0, u = 0, color = 0xFF000000 } end

local function rgb(r, g, b, f)
  local rr = math.floor(r * f); if rr < 0 then rr = 0 elseif rr > 255 then rr = 255 end
  local gg = math.floor(g * f); if gg < 0 then gg = 0 elseif gg > 255 then gg = 255 end
  local bb = math.floor(b * f); if bb < 0 then bb = 0 elseif bb > 255 then bb = 255 end
  return (255 << 24) | (rr << 16) | (gg << 8) | bb
end

local function draw_arc(st)
  if st.degenerate or st.progress <= 0 then return end
  local function pass(sprite, width, dome)
    local n = st.segments + 1
    local pts = RIBBON.points
    for i = 1, n do pts[i] = POINTS[i] end
    for i = n + 1, #pts do pts[i] = nil end
    RIBBON.sprite = sprite
    RIBBON.depth = st.depth or settings.depth.effect
    for i = 1, n do
      local t = ((i - 1) / st.segments) * st.progress
      local x, y = arc_point(st, t)
      local x2, y2 = arc_point(st, t + 0.02)
      local tx, ty = x2 - x, y2 - y
      local len = math.sqrt(tx * tx + ty * ty)
      local jx, jy = 0, 0
      if len > 0 then
        jx, jy = -ty / len, tx / len
      end
      local j = (st.noise_vals[((i - 1) % #st.noise_vals) + 1] or 0) * st.noise
      local f = clamp01(dome * t * (1 - t) + 0.15)
      local p = POINTS[i]
      p.x, p.y = x + jx * j, y + jy * j
      p.width, p.u = f * width, t
      p.color = rgb(st.r, st.g, st.b, f)
    end
    wa.draw.ribbon(RIBBON)
  end
  pass(settings.beam, st.core_w, st.core_dome)
  if st.glow_w > 0 then pass(settings.glow, st.glow_w, st.glow_dome) end
end

local QUAD = { blend = "add", points = { {}, {}, {}, {} } }
local function draw_quad_at(sprite, x, y, size, color, depth, frame)
  if not sprite or not x or not y then return end
  local h = size * 0.5
  local p = QUAD.points
  p[1].x, p[1].y = x - h, y - h
  p[2].x, p[2].y = x + h, y - h
  p[3].x, p[3].y = x + h, y + h
  p[4].x, p[4].y = x - h, y + h
  QUAD.sprite, QUAD.color, QUAD.depth, QUAD.frame = sprite, color, depth, frame or 0
  wa.draw.quad(QUAD)
end

local function spark_frame(s)
  local frame = math.floor(s.phase * s.frames)
  if frame < 0 then frame = 0 elseif frame >= s.frames then frame = s.frames - 1 end
  return frame
end

local function draw_spark(s)
  if s.phase > 1 then return end
  local size = s.cell * s.size
  draw_quad_at(s.sprite, s.x, s.y, size, rgb(s.r, s.g, s.b, 1),
    s.depth or settings.depth.spark, spark_frame(s))
end

local function draw_glow(g)
  local size = g.cell * g.size
  local color = rgb(g.r, g.g, g.b, 1)
  for _ = 1, g.passes do
    draw_quad_at(g.sprite, g.x, g.y, size, color,
      g.depth or settings.depth.glow, 0)
  end
end

-- The electric explosion: DrawExplosion and DrawEllipse (effects_methods.c:80-98,
-- px_effects.c:898-988).
local function fill_burst_noise(b)
  local n = b.segments
  for i = 1, n do b.noise_vals[i] = rand_float(b.rng, -1, 1) end
  for i = n + 1, #b.noise_vals do b.noise_vals[i] = nil end
end

local function seg_count(v, radius, mul)
  local n
  if v == nil then n = math.floor(radius * mul)
  elseif v < 10 then n = math.floor(radius * v)
  else n = math.floor(v) end
  if n < 8 then n = 8 elseif n > 255 then n = 255 end
  return n
end

local function burst_state(o)
  local radius = o.radius or 0
  if radius <= 0 then return nil end
  local b = {
    x = o.x or 0, y = o.y or 0, radius = radius,
    r = o.r or 100, g = o.g or 150, b = o.b or 220,
    noise = o.noise or 1.1, duration = o.duration or 18,
    fade = o.fade or 0.55, grow = o.grow or 3.0,
    live = o.live or 24, age = 0, timer = 0,
    segments = seg_count(o.segments, radius, 1.2),
    thickness = o.thickness or 15,
    ellipse = o.ellipse or { 1.25, 0.45 },
    rebuffer = o.rebuffer, depth = o.depth, done = false,
    rng = new_rng(o), noise_vals = {},
  }
  if b.rebuffer == nil then
    b.rebuffer = { at = 16, noise = 1.8, r = 120, g = 170, b = 240,
      fade = -0.85, segments = 1.30 }
  end
  b.rebuffer.at = b.rebuffer.at or 16
  b.rebuffer.segments = seg_count(b.rebuffer.segments, radius, 1.3)
  fill_burst_noise(b)
  return b
end

local function update_burst(b)
  b.age = b.age + 1
  b.timer = b.timer + b.fade
  if b.age == b.rebuffer.at then
    b.noise = b.rebuffer.noise or b.noise
    b.r, b.g, b.b = b.rebuffer.r or b.r, b.rebuffer.g or b.g,
      b.rebuffer.b or b.b
    b.fade = b.rebuffer.fade or b.fade
    b.segments = b.rebuffer.segments or b.segments
    fill_burst_noise(b)
  elseif b.age % 3 == 0 then
    fill_burst_noise(b)
  end
  if b.age > b.live then b.done = true end
end

local function draw_burst(b)
  if b.done or b.age > b.live then return end
  local p = clamp01(b.timer / b.duration)
  local env = 1 - p
  local radius = b.radius * (1 + b.grow * p)
  local n = b.segments
  local angle_step = 2 * math.pi / n
  local function pass(sprite, width, lens)
    local pts = RIBBON.points
    for i = 1, n + 1 do pts[i] = POINTS[i] end
    for i = n + 2, #pts do pts[i] = nil end
    RIBBON.sprite, RIBBON.depth = sprite, b.depth or settings.depth.burst
    for i = 1, n + 1 do
      local a = angle_step * (i - 1)
      local j = (b.noise_vals[((i - 1) % #b.noise_vals) + 1] or 0)
        * radius * 0.08 * b.noise
      local rx, ry = radius + j, radius + j
      if lens then rx, ry = radius * b.ellipse[1] + j, radius * b.ellipse[2] + j end
      local q = POINTS[i]
      q.x = b.x + wa.math.cos(a) * rx
      q.y = b.y + wa.math.sin(a) * ry
      q.width, q.u = width, (i - 1) / n
      q.color = rgb(b.r, b.g, b.b, env)
    end
    wa.draw.ribbon(RIBBON)
  end
  local half = math.max(0.90 * b.thickness * env, 1.8)
  pass(settings.beam, 2 * half, false)
  pass(settings.glow, 2 * b.thickness * env, false)
  local lens_half = math.max(b.thickness * env, 1.4)
  pass(settings.beam, 2 * lens_half, true)
  pass(settings.glow, 2 * b.thickness * env, true)
end

local function update_spark(s)
  s.phase = s.phase + s.rate
  if s.phase > 1 + s.pause then s.phase = 0 end
  s.age = s.age + 1
  if s.life and s.age > s.life then s.done = true end
end

local function update_glow(g)
  g.age = g.age + 1
  if g.life and g.age > g.life then g.done = true end
end

-- PX's persistent CEffectManager loop (type 0 ring, type 6 thin spin). The
-- caller owns the lifetime; the saw detaches it when the electric mode ends.
local function fill_ring_noise(st)
  local n = st.segments + 1
  for i = 1, n do st.noise_vals[i] = rand_float(st.rng, -1, 1) end
  for i = n + 1, #st.noise_vals do st.noise_vals[i] = nil end
end

local function update_ring(st)
  if st.done then return end
  if st.follow then
    local x, y = st.follow()
    if x == nil then st.done = true; return end
    st.x, st.y = x, y
  end
  st.age = st.age + 1
  st.angle = st.angle + st.speed
  if st.age % 2 == 0 then fill_ring_noise(st) end
end

local function draw_ring(st)
  if st.done then return end
  local n = st.segments
  local function pass(sprite, width, scale, color, noise_scale)
    local pts = RIBBON.points
    for i = 1, n + 1 do pts[i] = POINTS[i] end
    for i = n + 2, #pts do pts[i] = nil end
    RIBBON.sprite, RIBBON.depth = sprite, st.depth or settings.depth.ring
    for i = 1, n + 1 do
      local j = (st.noise_vals[((i - 1) % #st.noise_vals) + 1] or 0)
        * st.noise * (noise_scale or 1)
      local a = st.angle + (i - 1) * (2 * math.pi / n)
      local rr = (st.radius + j) * (scale or 1)
      local p = POINTS[i]
      p.x = st.x + wa.math.cos(a) * rr
      p.y = st.y + wa.math.sin(a) * rr
      p.width, p.u = width, (i - 1) / n
      -- PX's thin spin narrows and dims to the arc ends (:1019-1027).
      if st.thin then
        local t = (i - 1) / n
        local f = 4 * t * (1 - t) + 0.15
        if f > 1 then f = 1 end
        p.width = width * f
        p.color = rgb(st.r, st.g, st.b, f)
      else
        p.color = color or rgb(st.r, st.g, st.b, 1)
      end
    end
    wa.draw.ribbon(RIBBON)
  end
  local core = rgb(st.r, st.g, st.b, 1)
  local glow = rgb(st.r * 0.72, st.g * 0.72, st.b * 0.72, 1)
  -- PX DrawRingFX: a dim under-beam at 0.85 radius, the core, then the wide
  -- glow. Type 6 (thin spin) is the single tapered core pass only.
  if not st.thin then pass(settings.beam, st.core_w, 0.85, glow, 0.5) end
  pass(settings.beam, st.core_w, 1, core)
  if st.glow_w > 0 and not st.thin then pass(settings.glow, st.glow_w, 1, glow) end
end

local function update_smoke(sm)
  for i = #sm.parts, 1, -1 do
    local p = sm.parts[i]
    p.vx, p.vy = p.vx * (1 - p.drag), p.vy * (1 - p.drag)
    p.x, p.y = p.x + p.vx, p.y + p.vy
    p.age = p.age + 1
    if p.age >= p.life then table.remove(sm.parts, i) end
  end
  if #sm.parts == 0 then sm.done = true end
end

local function draw_smoke(sm)
  for _, p in ipairs(sm.parts) do
    local f = 1 - p.age / p.life
    local a = math.floor(255 * f)
    if a < 0 then a = 0 end
    local color = (a << 24) | (p.r << 16) | (p.g << 8) | p.b
    draw_quad_at(sm.sprite, p.x, p.y, p.size, color,
      sm.depth or settings.depth.smoke, 0)
  end
end

local draw, tick, ensure_driver
local draw_warned = false

local function make_smoke_parts(sm, o)
  local kinds = o.kinds or 2
  local count = o.count or 7
  local spread = o.spread or 2.0
  local up = o.up or { 4.5, 7.0 }
  local life = o.life or { 27, 52 }
  for kind = 1, kinds do
    for _ = 1, count do
      local p = {
        x = sm.x + rand_float(sm.rng, -4, 4),
        y = sm.y + rand_float(sm.rng, -4, 4),
        age = 0, drag = o.drag or 0.10,
      }
      if kind == 1 then
        p.r, p.g, p.b = math.floor((o.r or 100) * 0.91),
          math.floor((o.g or 120) * 0.92), math.floor((o.b or 190) * 0.92)
        p.vx, p.vy = rand_float(sm.rng, -spread, spread),
          -rand_float(sm.rng, up[1], up[2])
        p.size = (o.size or 32) + rand_int(sm.rng, -6, 6)
        p.life = rand_int(sm.rng, life[1], life[2])
      else
        p.r, p.g, p.b = o.r or 100, o.g or 120, o.b or 190
        p.vx, p.vy = rand_float(sm.rng, -1.5, 1.5),
          rand_float(sm.rng, -2.3, 2.3)
        p.size = (o.size or 28) + rand_int(sm.rng, -6, 6)
        p.life = rand_int(sm.rng, life[1], life[2])
      end
      sm.parts[#sm.parts + 1] = p
    end
  end
end

local function make_smoke(o)
  local sm = {
    x = o.x or 0, y = o.y or 0, parts = {}, done = false,
    sprite = o.sprite or settings.smoke, depth = o.depth,
    rng = new_rng(o),
  }
  make_smoke_parts(sm, o)
  smokes[#smokes + 1] = sm
  ensure_driver(o.owner)
  sm.remove = function(self) self.done = true end
  return sm
end

local function draw_emitter(e)
  if e.dead or e.ready == false then return end
  if e.spark then
    e.spark.phase = e.spark_phase
    draw_spark(e.spark)
  end
  if e.glow then draw_glow(e.glow) end
  for _, a in ipairs(e.arcs) do draw_arc(a) end
end

draw = function()
  local function safe(fn, item)
    local ok, err = pcall(fn, item)
    if not ok and not draw_warned then
      draw_warned = true
      if wa.log then wa.log("px_effects draw: " .. tostring(err)) end
    end
  end
  for _, sm in ipairs(smokes) do safe(draw_smoke, sm) end
  for _, e in ipairs(emitters) do safe(draw_emitter, e) end
  for _, a in ipairs(arcs) do safe(draw_arc, a) end
  for _, b in ipairs(bursts) do safe(draw_burst, b) end
  for _, s in ipairs(sparks) do safe(draw_spark, s) end
  for _, g in ipairs(glows) do safe(draw_glow, g) end
  for _, r in ipairs(rings) do safe(draw_ring, r) end
end

ensure_driver = function(owner)
  if driver then return end
  driver = wa.actors.spawn({
    sprite = false, x = 0, y = 0, gravity = false, collide = false,
    persist = true, drown = false, owner = owner or current_worm(),
    on = function(a) tick(a) end,
  })
end
local function start_ray(e, i)
  local r = e.reach
  local a = make_arc({
    from_x = e.x, from_y = e.y,
    to_x = e.x + rand_int(e, -r.distance, r.distance),
    to_y = e.y + rand_int(e, -r.distance, r.distance),
    terrain = r.terrain, curve = r.curve,
    bulge = rand_int(e, r.bulge[1], r.bulge[2]),
    speed = rand_float(e, r.speed[1], r.speed[2]),
    noise = r.noise, segments = r.segments,
    core_w = r.core_w, glow_w = r.glow_w,
    core_dome = r.core_dome, glow_dome = r.glow_dome,
    r = r.r, g = r.g, b = r.b, depth = r.depth, owner = e.owner, rng = e,
  })
  a.ray_index = i
  e.arcs[#e.arcs + 1] = a
end

local function has_ray(e, i)
  for _, a in ipairs(e.arcs) do
    if a.ray_index == i then return true end
  end
  return false
end

local function update_emitter(e)
  if e.trail and e.trail_key then
    trail.sample(e.trail_key, e.x, e.y, e.vx, e.vy)
  end
  local sp = e.spark
  if sp then
    sp.phase = e.spark_phase + sp.rate
    if sp.phase > 1 + sp.pause then sp.phase = 0 end
    e.spark_phase = sp.phase
    sp.x, sp.y = e.x, e.y
  end
  if e.glow then e.glow.x, e.glow.y = e.x, e.y end
  for i = #e.arcs, 1, -1 do
    local a = e.arcs[i]
    update_arc(a)
    if a.done then
      local ray = a.ray_index
      table.remove(e.arcs, i)
      if ray then
        e.cooldowns[ray] = rand_int(e, e.reach.cooldown[1], e.reach.cooldown[2])
      end
    end
  end
  for i = 1, e.reach.count do
    if not has_ray(e, i) then
      e.cooldowns[i] = e.cooldowns[i] - 1
      if e.cooldowns[i] <= 0 then start_ray(e, i) end
    end
  end
end

tick = function(a)
  for i = #emitters, 1, -1 do
    local e = emitters[i]
    if e.dead then
      if e.trail_key then trail.drop(e.trail_key) end
      table.remove(emitters, i)
    else
      if e.follow then
        local x, y, vx, vy, ready = e.follow()
        if x == nil then
          e.dead = true
          if e.trail_key then trail.drop(e.trail_key) end
          table.remove(emitters, i)
        else
          e.x, e.y, e.vx, e.vy = x, y, vx or 0, vy or 0
          if ready ~= nil then e.ready = ready end
        end
      end
      if not e.dead and e.ready ~= false then update_emitter(e) end
    end
  end
  for i = #arcs, 1, -1 do
    local st = arcs[i]
    update_arc(st)
    if st.done and not st.persist then table.remove(arcs, i) end
  end
  for i = #bursts, 1, -1 do
    update_burst(bursts[i])
    if bursts[i].done then table.remove(bursts, i) end
  end
  for i = #sparks, 1, -1 do
    update_spark(sparks[i])
    if sparks[i].done then table.remove(sparks, i) end
  end
  for i = #glows, 1, -1 do
    update_glow(glows[i])
    if glows[i].done then table.remove(glows, i) end
  end
  for i = #smokes, 1, -1 do
    update_smoke(smokes[i])
    if smokes[i].done then table.remove(smokes, i) end
  end
  for i = #rings, 1, -1 do
    update_ring(rings[i])
    if rings[i].done then table.remove(rings, i) end
  end
  if #emitters == 0 and #arcs == 0 and #bursts == 0 and #sparks == 0
      and #glows == 0 and #smokes == 0 and #rings == 0 then
    driver = nil
    a:despawn()
  end
end

-- Call from install(ctx), after the bundle's sprite paths are known.
function fx.install(o)
  if installed then return end
  installed = true
  o = o or {}
  settings = {
    beam = o.beam or trail.BEAM,
    glow = o.glow or trail.GLOW,
    spark = o.spark or fx.SPARK,
    blob = o.blob or fx.BLOB,
    smoke = o.smoke or fx.SMOKE,
    trail = o.trail ~= false,
  }
  local d = o.depth or {}
  settings.depth = {
    spark = d.spark or wa.depth.FRONT,
    effect = d.effect or wa.depth.EFFECTS,
    burst = d.burst or wa.depth.EFFECTS,
    glow = d.glow or (wa.depth.OBJECTS + 0x1000),
    trail = d.trail or (wa.depth.OBJECTS + 1),
    smoke = d.smoke or wa.depth.EFFECTS,
    ring = d.ring or wa.depth.EFFECTS,
  }
  if settings.trail then trail.install() end
  wa.on.draw(draw)
end

function fx.emitter(o)
  if not installed then wa.log("px_effects: fx.install(ctx) first") return nil end
  o = o or {}
  local preset = fx.PRESETS[o.preset or "electric"] or fx.PRESETS.electric
  local spark = copy({}, preset.spark, SPARK_KEYS)
  copy(spark, o.spark, SPARK_KEYS)
  local glow = copy({}, preset.glow, GLOW_KEYS)
  copy(glow, o.glow, GLOW_KEYS)
  local reach = copy({}, preset.reach, REACH_KEYS)
  copy(reach, o.reach, REACH_KEYS)
  local tro = copy({}, preset.trail, TRAIL_KEYS)
  copy(tro, o.trail, TRAIL_KEYS)
  local e = {
    owner = o.owner, x = o.x or 0, y = o.y or 0,
    vx = o.vx or 0, vy = o.vy or 0, follow = o.follow,
    random = o.random or "lcg", seed = o.seed or new_seed(),
    spark = spark, glow = glow, reach = reach,
    trail = (o.trail ~= false and settings.trail) and tro or false,
    trail_key = next_key, arcs = {}, cooldowns = {}, spark_phase = 0,
    ready = o.ready ~= false, dead = false,
  }
  next_key = next_key - 1
  if e.trail then
    e.trail.depth = e.trail.depth or settings.depth.trail
    e.trail.beam = e.trail.beam or settings.beam
    e.trail.glow = e.trail.glow or settings.glow
    trail.add(e.trail_key, e.owner, e.trail)
  end
  spark.sprite = spark.sprite or settings.spark
  spark.depth = spark.depth or settings.depth.spark
  spark.phase = 0
  glow.sprite = glow.sprite or settings.blob
  glow.depth = glow.depth or settings.depth.glow
  glow.age = 0
  -- A draw can land before the first tick; the quad needs these now.
  spark.x, spark.y = e.x, e.y
  glow.x, glow.y = e.x, e.y
  local base = rand_int(e, reach.first[1], reach.first[2])
  for i = 1, reach.count do
    e.cooldowns[i] = base + (i - 1) * reach.stagger
  end
  emitters[#emitters + 1] = e
  ensure_driver(e.owner)
  e.move_to = function(self, x, y) self.x, self.y = x, y end
  e.reach_to = function(self, x, y, opts)
    opts = opts or {}
    local a = make_arc({
      from_x = self.x, from_y = self.y, to_x = x, to_y = y,
      terrain = (opts.terrain ~= nil) and opts.terrain or false,
      curve = self.reach.curve,
      bulge = opts.bulge or 5,
      speed = opts.speed or 0.079,
      noise = self.reach.noise, segments = self.reach.segments,
      core_w = self.reach.core_w, glow_w = self.reach.glow_w,
      r = self.reach.r, g = self.reach.g, b = self.reach.b,
      depth = self.reach.depth, owner = self.owner, rng = self,
    })
    self.arcs[#self.arcs + 1] = a
    return a
  end
  e.burst = function(self, opts)
    opts = opts or {}
    local b = fx.burst({
      x = self.x, y = self.y, radius = opts.radius,
      smoke = opts.smoke, preset = opts.preset,
      r = opts.r, g = opts.g, b = opts.b,
    })
    self:remove()
    return b
  end
  e.remove = function(self)
    self.dead = true
    if self.trail_key then trail.drop(self.trail_key) end
    if self.tracker and self.tracker.release then self.tracker.release() end
  end
  return e
end

function fx.ring(o)
  if not installed then wa.log("px_effects: fx.install(ctx) first") return nil end
  o = o or {}
  local st = copy({}, o, RING_KEYS)
  st.radius = o.radius or 0
  if st.radius <= 0 then return nil end
  st.x, st.y = o.x or 0, o.y or 0
  st.segments = math.min(255, math.max(8, math.floor(o.segments or 24)))
  st.noise = o.noise or 0.67
  st.r, st.g, st.b = o.r or 130, o.g or 180, o.b or 255
  st.speed = o.speed or 0
  st.angle = o.angle or 0
  -- PX beamThiccness is a half width (TexturedBeamPoint lays at +-dx), and
  -- wa.draw.ribbon wants the full one, so double it. PX's beam glow is three
  -- half-widths, not the single-glow radius formula. The beam texture lights
  -- only about a third of the ribbon, so PX's 2.3 half-width floor reads as
  -- ~1.4 px; floor the core at 3.2 half (6.4 full) for ~2 px visible even on
  -- the smallest saw. The glow keeps PX's 3x low-clamped width.
  local px_core = st.radius / 10
  if px_core < 2.3 then px_core = 2.3 end
  local px_glow = px_core * 3
  if px_core > 5.5 then px_core = 5.5 end
  local core = px_core
  if core < 3.2 then core = 3.2 end
  st.core_w = o.core_w or core * 2
  st.glow_w = o.glow_w or px_glow * 2
  st.thin = o.thin and true or false
  st.age, st.done = 0, false
  st.rng = new_rng(o)
  st.noise_vals = {}
  fill_ring_noise(st)
  rings[#rings + 1] = st
  ensure_driver(o.owner)
  st.remove = function(self)
    if type(self) == "table" then self.done = true else st.done = true end
  end
  st.set_radius = function(self, radius)
    if type(self) == "number" then self, radius = st, self end
    self.radius = radius
  end
  return st
end

function fx.thin_spin(o)
  o = o or {}
  o.thin = true
  o.glow_w = o.glow_w or 0
  -- PX DrawThinSpinFX: half width 6*objectScale, objectScale = 2*radius/100;
  -- doubled for wa.draw.ribbon. Floor the max at 6.4 full (~2 px visible) so
  -- a small saw's arc is not a hairline; the dome taper is in draw_ring.
  o.core_w = o.core_w or math.max(6.4, 0.24 * (o.radius or 0))
  return fx.ring(o)
end

function fx.arc(o)
  if not installed then wa.log("px_effects: fx.install(ctx) first") return nil end
  o = o or {}
  local a = make_arc(o)
  if a.degenerate then return nil end
  arcs[#arcs + 1] = a
  ensure_driver(o.owner)
  return a
end

function fx.burst(o)
  if not installed then wa.log("px_effects: fx.install(ctx) first") return nil end
  o = o or {}
  local preset = fx.PRESETS[o.preset or "electric"] or fx.PRESETS.electric
  local b = copy({}, preset.burst, BURST_KEYS)
  copy(b, o, BURST_KEYS)
  if type(b.rebuffer) == "table" then
    b.rebuffer = copy({}, b.rebuffer, REBUFFER_KEYS)
  end
  if type(b.ellipse) == "table" then
    b.ellipse = { b.ellipse[1] or b.ellipse.x or 1.25,
      b.ellipse[2] or b.ellipse.y or 0.45 }
  end
  b.x, b.y, b.radius = o.x or 0, o.y or 0, o.radius
  b.rng = new_rng(o)
  local st = burst_state(b)
  if not st then return nil end
  bursts[#bursts + 1] = st
  ensure_driver(o.owner)
  if o.smoke ~= false and b.smoke ~= false then
    local src = b.smoke
    if src == true then src = {} end
    if type(src) == "table" then
      local sm = copy({}, src, SMOKE_KEYS)
      if type(o.smoke) == "table" then copy(sm, o.smoke, SMOKE_KEYS) end
      sm.x, sm.y, sm.owner = st.x, st.y, o.owner
      sm.rng = st.rng
      sm.sprite = sm.sprite or settings.smoke
      make_smoke(sm)
    end
  end
  return st
end

function fx.spark(o)
  if not installed then wa.log("px_effects: fx.install(ctx) first") return nil end
  o = o or {}
  local s = copy({}, fx.PRESETS.electric.spark, SPARK_KEYS)
  copy(s, o, SPARK_KEYS)
  s.x, s.y = o.x or 0, o.y or 0
  s.sprite = s.sprite or settings.spark
  s.phase, s.age = 0, 0
  sparks[#sparks + 1] = s
  ensure_driver(o.owner)
  s.remove = function(self) self.done = true end
  return s
end

function fx.glow(o)
  if not installed then wa.log("px_effects: fx.install(ctx) first") return nil end
  o = o or {}
  local g = copy({}, fx.PRESETS.electric.glow, GLOW_KEYS)
  copy(g, o, GLOW_KEYS)
  g.x, g.y = o.x or 0, o.y or 0
  g.sprite = g.sprite or settings.blob
  g.age, g.done = 0, false
  glows[#glows + 1] = g
  ensure_driver(o.owner)
  g.remove = function(self) self.done = true end
  return g
end

function fx.smoke(o)
  if not installed then wa.log("px_effects: fx.install(ctx) first") return nil end
  o = o or {}
  local sm = copy({}, fx.PRESETS.electric.burst.smoke, SMOKE_KEYS)
  copy(sm, o, SMOKE_KEYS)
  sm.x, sm.y, sm.owner = o.x or 0, o.y or 0, o.owner
  sm.rng = new_rng(o)
  sm.sprite = sm.sprite or settings.smoke
  return make_smoke(sm)
end

-- A round crater. PX's MakeHole (custom_explosion.c:134-137); sim only.
function fx.crater(o)
  if not o then return end
  local shape = o.shape or "circle"
  local r = math.floor(o.radius or 0)
  if shape == "circle" then
    if r < 1 then return end
    if r > 200 then r = 200 end
  end
  wa.land.cut({ x = o.x, y = o.y, shape = shape, radius = r,
    sprite = o.sprite, frame = o.frame })
end

-- Follow a mine a weapon just placed. on_place carries no handle, so claim the
-- nearest unclaimed mine near the placement point; id+uid detect its removal.
local claimed = {}
function fx.tracker(o)
  o = o or {}
  local group = o.group or wa.mines
  local x0, y0, radius = o.x or 0, o.y or 0, o.radius or 16
  local give_up = o.give_up or 30
  local id, uid, tries
  local function release()
    if id ~= nil then
      claimed[id] = nil
      id, uid = nil, nil
    end
  end
  local function follow()
    local list = group.all()
    if id == nil then
      tries = (tries or 0) + 1
      if tries > give_up then return nil end
      local best, bestd
      for _, m in ipairs(list) do
        if claimed[m.id] == nil then
          local dx, dy = m.x - x0, m.y - y0
          local d = dx * dx + dy * dy
          if d <= radius * radius and (not bestd or d < bestd
              or (d == bestd and m.id > best.id)) then
            best, bestd = m, d
          end
        end
      end
      if best then
        id, uid = best.id, best.uid
        claimed[id] = uid or true
        return best.x, best.y, best.vx, best.vy, true
      end
      return x0, y0, 0, 0, false
    end
    for _, m in ipairs(list) do
      if m.id == id and (uid == nil or m.uid == uid) then
        return m.x, m.y, m.vx, m.vy, true
      end
    end
    claimed[id] = nil
    return nil
  end
  return setmetatable({ release = release }, {
    __call = function(_, ...) return follow(...) end,
  })
end

function fx.mine(o)
  o = o or {}
  local t = fx.tracker({
    x = o.x, y = o.y, radius = o.radius, group = o.group,
    give_up = o.give_up,
  })
  local opts = {
    owner = o.owner, x = o.x, y = o.y, vx = o.vx, vy = o.vy,
    follow = t, preset = o.preset, random = o.random, seed = o.seed,
    spark = o.spark, glow = o.glow, reach = o.reach, trail = o.trail,
    -- Hold the spark and bolts until the tracker has the mine: until then
    -- its x/y is only the placement point.
    ready = false,
  }
  local e = fx.emitter(opts)
  if e then e.tracker = t end
  return e, t
end

return fx
