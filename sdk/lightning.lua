-- Lightning: a bolt from the sky with its cloud and flash, and what it strikes.

local lightning = {}

local BEAM = "wf-lib/px/sprites/lightning/beam.png"
local GLOW = "wf-lib/px/sprites/lightning/glow.png"
local CLOUD = "wf-lib/px/sprites/lightning/cloud.png"
local THUNDER = "wf-lib/px/sounds/lightning/thunder.wav"
local HIT = "wf-lib/px/sounds/lightning/hit.wav"
lightning.BEAM, lightning.GLOW, lightning.CLOUD = BEAM, GLOW, CLOUD
lightning.THUNDER, lightning.HIT = THUNDER, HIT
lightning.SPRITES = { BEAM, GLOW, CLOUD }
lightning.SOUNDS = { THUNDER, HIT }

-- The bolt's light blue.
local LR, LG, LB = 120, 140, 255
lightning.R, lightning.G, lightning.B = LR, LG, LB

local function sq(v) return v * v end
local function lerp(t, a, b) return a + (b - a) * t end
lightning.lerp = lerp

-- Behind the terrain: the land hides the bolt and its cloud.
function lightning.depth() return wa.depth.BEHIND_TERRAIN end
function lightning.cloud_depth() return wa.depth.BEHIND_TERRAIN - 0x1000 end

-- The strikes still drawn, and what the strike asks of the bundle.
local strikes = {}
lightning.strikes = strikes
local HOOKS = { "beam", "before_hit", "heals", "revived", "after_hit" }
local hooks = {}
for _, key in ipairs(HOOKS) do hooks[key] = {} end

function lightning.extend(h)
  for _, key in ipairs(HOOKS) do
    if h[key] then hooks[key][#hooks[key] + 1] = h[key] end
  end
end

-- An invisible actor that runs `frame` every frame.
function lightning.effect_actor(x, y, owner, frame)
  return wa.actors.spawn({
    sprite = GLOW, visible = false, gravity = false, collide = false,
    owner = owner, x = x, y = y, on = frame,
  })
end

-- Worms, mines, crates, oil drums and, with `graves`, gravestones.
function lightning.targets(graves)
  local out = {}
  for _, group in ipairs({ wa.worms, wa.mines, wa.crates, wa.oil }) do
    for _, obj in ipairs(group.all()) do out[#out + 1] = obj end
  end
  if graves and wa.graves then
    for _, obj in ipairs(wa.graves.all()) do out[#out + 1] = obj end
  end
  return out
end

function lightning.target_radius(obj)
  if obj.radius then return obj.radius end
  if obj.kind == "worm" then return 6 end
  if obj.kind == "grave" then return 8 end
  if obj.kind == "mine" then return 5 end
  return 9
end

-- The first land or target along a ray: `{ x, y, obj }`, or nil.
function lightning.trace(x0, y0, dx, dy)
  local far = 10000
  if wa.world.electrical_trace then
    return wa.world.electrical_trace(x0, y0,
      (x0 + dx * far), (y0 + dy * far))
  end
  local land = wa.land.trace(x0, y0,
    (x0 + dx * far), (y0 + dy * far))
  local best = land and math.sqrt(sq(land.x - x0) + sq(land.y - y0)) or far
  local hit = land and { x = land.x, y = land.y, obj = nil } or nil
  for _, obj in ipairs(lightning.targets(true)) do
    local ox, oy = (obj.x - x0), (obj.y - y0)
    local along = ox * dx + oy * dy
    local across = math.abs(ox * dy - oy * dx)
    if along > 0 and along < best and across <= lightning.target_radius(obj) then
      best = along
      hit = { x = obj.x, y = obj.y, obj = obj }
    end
  end
  return hit
end

local STRIKE_HALF_WIDTH = 4

local function struck(s, obj, length)
  local ox, oy = obj.x - s.sx, obj.y - s.sy
  local along = ox * s.dirx + oy * s.diry
  local across = math.abs(ox * s.diry - oy * s.dirx)
  if along >= 0 and along <= length and across <= STRIKE_HALF_WIDTH + lightning.target_radius(obj) then
    return true
  end
  if not s.hit then return false end
  local dx, dy = obj.x - s.ex, obj.y - s.ey
  local r = lightning.target_radius(obj) + 6
  return dx * dx + dy * dy <= r * r
end

-- Heals worms on the line by 25, revives graves, starts mines, hits crates and oil drums.
local function strike_hit(s)
  for _, f in ipairs(hooks.before_hit) do f(s) end
  local length = math.sqrt(sq(s.ex - s.sx) + sq(s.ey - s.sy))
  local targets = wa.world.electrical_nearby
    and wa.world.electrical_nearby((s.sx + s.ex) / 2, (s.sy + s.ey) / 2,
      math.ceil(length / 2) + STRIKE_HALF_WIDTH + 9 + 6, true)
    or lightning.targets(true)
  for _, obj in ipairs(targets) do
    if struck(s, obj, length) then
      if obj.kind == "worm" then
        local heals = true
        for _, f in ipairs(hooks.heals) do
          if f(obj) == false then heals = false; break end
        end
        if heals then obj:heal(25) end
      elseif obj.kind == "grave" then
        if obj.worm_id ~= 0 then
          local worm = obj:revive(obj.worm_id, s.revive_health)
          if worm then
            for _, f in ipairs(hooks.revived) do f(worm) end
          elseif s.refused_sound then
            wa.sound.play(obj, s.refused_sound)
          end
        end
      elseif obj.kind == "mine" then
        obj:arm(obj.fuse < 0 and wa.random(1000, 5000) or obj.fuse)
      elseif obj.kind == "crate" or obj.kind == "oil" then
        obj:hit(100, 0, 0)
      end
    end
  end
  for _, f in ipairs(hooks.after_hit) do
    f(s, function(obj) return struck(s, obj, length) end)
  end
end

local function strike_rand(s)
  s.seed = (s.seed * 1103515245 + 12345) % 0x80000000
  return s.seed / 0x80000000
end

local function strike_puff(s, life, drag, s0, s1)
  local xvel = strike_rand(s) * 2 - 1
  local yvel = 1 - xvel * xvel
  s.cloud[#s.cloud + 1] = { x = s.sx, y = s.sy, vx = 16 * xvel,
    vy = (strike_rand(s) * 9 - 8) * yvel, drag = drag, age = 0, life = life, s0 = s0, s1 = s1 }
end

local function strike_particles(s)
  if s.tail > 0 then
    s.cloud_timer = s.cloud_timer - 1
    if s.cloud_timer <= 0 then
      if s.life > 0 then strike_puff(s, 100, 0.3, 1.2, 0.6) end
      strike_puff(s, 140, 0.15, 1.0, 0.01)
      s.cloud_timer = 2
    end
    if s.delay == 0 and s.life > 0 and s.hit then
      local a = strike_rand(s) * 2 * math.pi
      local v = (1 + strike_rand(s) * 2)
      s.sparks[#s.sparks + 1] = { x = s.ex, y = s.ey, vx = wa.math.cos(a) * v, vy = wa.math.sin(a) * v, age = 0 }
    end
  end
  for i = #s.cloud, 1, -1 do
    local p = s.cloud[i]
    p.age = p.age + 1
    if p.age >= p.life then
      table.remove(s.cloud, i)
    else
      p.x, p.y = p.x + p.vx, p.y + p.vy
      p.vx, p.vy = p.vx * (1 - p.drag), p.vy * (1 - p.drag)
    end
  end
  for i = #s.sparks, 1, -1 do
    local p = s.sparks[i]
    p.age = p.age + 1
    if p.age >= 50 then
      table.remove(s.sparks, i)
    else
      p.x, p.y, p.vy = p.x + p.vx, p.y + p.vy, p.vy + 1 / 8
    end
  end
end

function lightning.strike(spec)
  local dirx = 0.5 * ((spec.side or 1) < 0 and -1 or 1)
  local diry = math.sqrt(3) / 2
  local sy = -270
  local sx = (spec.x - (spec.y - sy) * dirx / diry)
  local hit = lightning.trace(sx, sy, dirx, diry)
  local ex, ey = hit and hit.x or sx + (300 * dirx),
    hit and hit.y or sy + (300 * diry)
  for _, f in ipairs(hooks.beam) do
    ex, ey, hit = f(sx, sy, dirx, diry, ex, ey, hit)
  end
  local distance = math.sqrt(sq(ex - sx) + sq(ey - sy))
  if hit and distance > 300 then
    sx, sy = ex - (300 * dirx), ey - (300 * diry)
  end
  local s = { sx = sx, sy = sy, ex = ex, ey = ey, hit = hit, dirx = dirx, diry = diry,
    delay = 150, life = 16, tail = 60, owner = spec.owner, alliance = spec.alliance,
    effects = spec.effects ~= false, revive_health = spec.revive_health or 10,
    refused_sound = spec.refused_sound, ticks = 0,
    seed = (ex // 1 * 7919 + ey // 1) % 0x80000000, cloud_timer = 0, cloud = {}, sparks = {} }
  strikes[#strikes + 1] = s
  if spec.thunder_on then wa.sound.play(spec.thunder_on, THUNDER) end
  local effect = lightning.effect_actor(ex, ey, spec.owner, function(a)
    s.ticks = s.ticks + 1
    strike_particles(s)
    if s.delay > 0 then
      s.delay = s.delay - 1
      if s.delay == 0 then wa.sound.play(a, HIT) end
    elseif s.life > 0 then
      s.life = s.life - 1
      if s.life == 0 and s.effects then strike_hit(s) end
    elseif s.tail > 0 then
      s.tail = s.tail - 1
    elseif #s.cloud == 0 and #s.sparks == 0 then
      for i, held in ipairs(strikes) do
        if held == s then table.remove(strikes, i); break end
      end
      a:despawn()
    end
  end)
  if not spec.thunder_on and effect then wa.sound.play(effect, THUNDER) end
  return s
end

-- How bright a strike's flash is, 0..1 (draw callbacks only).
function lightning.flash(s)
  if s.delay >= 8 then return 0 end
  if s.delay > 0 then return 0.3 + 0.4 * (8 - s.delay) / 8 end
  if s.life > 0 then return s.flicker or 1 end
  local f = 1 - (60 - s.tail + (wa.draw.fraction and wa.draw.fraction() or 0)) / 8
  return f > 0 and 0.5 * f * f or 0
end

-- Drawing helpers, made once the sheets are loaded.
local gfx
function lightning.gfx()
  if gfx then return gfx end
  local beam_sprite = wa.sprites.key(BEAM)
  local glow_sprite = wa.sprites.key(GLOW)
  local cloud_sprite = wa.sprites.key(CLOUD)
  local ELECTRIC_DEPTH = lightning.depth()
  local CLOUD_DEPTH = lightning.cloud_depth()
  local function colour(a, r, g, b)
    return (math.floor(a) << 24) | (r << 16) | (g << 8) | b
  end
  local QUAD = { points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} } }
  local function square(sprite, frame, blend, color, depth, x, y, hw, hh)
    QUAD.sprite, QUAD.frame, QUAD.blend, QUAD.color, QUAD.depth = sprite, frame, blend, color, depth
    local p = QUAD.points
    p[1][1], p[1][2] = x - hw, y - hh
    p[2][1], p[2][2] = x + hw, y - hh
    p[3][1], p[3][2] = x + hw, y + hh
    p[4][1], p[4][2] = x - hw, y + hh
    wa.draw.quad(QUAD)
  end
  local function glow(x, y, size, color)
    local h = size / 2
    square(glow_sprite, 0, "add", color, ELECTRIC_DEPTH, x, y, h, h)
  end
  local RIBBON = { sprite = beam_sprite, blend = "add", depth = ELECTRIC_DEPTH, points = {} }
  local POINTS = {}
  local function point(i, x, y, width, u, color)
    local p = POINTS[i]
    if not p then p = {}; POINTS[i] = p end
    RIBBON.points[i] = p
    p.x, p.y, p.width, p.u, p.color = x, y, width, u, color
  end
  local function ribbon(n)
    local pts = RIBBON.points
    for i = #pts, n + 1, -1 do pts[i] = nil end
    wa.draw.ribbon(RIBBON)
  end
  local function noise_span(noise, off, divs, scale, first, last)
    for i = 0, divs - 1 do noise[off + i] = 0 end
    noise[off], noise[off + divs - 1] = first, last
    local k = divs
    local l = k >> 1
    while l > 0 do
      for i = l, divs - 1 - l, k do
        noise[off + i] = (noise[off + i - l] + noise[off + i + l]) * 0.5 + (wa.draw.random() * 2 - 1) * scale
      end
      k = l
      l = k >> 1
    end
  end

  -- Puffs drawn dark, then lit corner by corner near the light, which falls off faster upwards.
  local DARK = { sprite = cloud_sprite, frame = 0, blend = "alpha", depth = CLOUD_DEPTH, quads = {}, count = 0 }
  local GLOWS = { sprite = cloud_sprite, frame = 0, blend = "add", depth = CLOUD_DEPTH - 0x200, quads = {}, count = 0 }
  local LIT = { sprite = cloud_sprite, frame = 0, blend = "alpha", depth = CLOUD_DEPTH - 0x100,
    points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} }, colors = { 0, 0, 0, 0 } }
  local function batch(b, n, pts, color)
    if not wa.draw.quads then
      QUAD.sprite, QUAD.frame, QUAD.blend, QUAD.color, QUAD.depth = b.sprite, 0, b.blend, color, b.depth
      local q = QUAD.points
      for i = 1, 4 do q[i][1], q[i][2] = pts[i][1], pts[i][2] end
      wa.draw.quad(QUAD)
      return n
    end
    local l = b.quads
    l[n + 1], l[n + 2], l[n + 3], l[n + 4] = pts[1][1], pts[1][2], pts[2][1], pts[2][2]
    l[n + 5], l[n + 6], l[n + 7], l[n + 8] = pts[3][1], pts[3][2], pts[4][1], pts[4][2]
    l[n + 9] = color
    return n + 9
  end
  local DEFAULT_DARK = { 45, 40, 60 }
  local function draw_cloud(puffs, lx, ly, power, reach, spread, style)
    local depth = style and style.depth or CLOUD_DEPTH
    local dark_rgb = style and style.dark or DEFAULT_DARK
    local fade = style and style.alpha or 1
    DARK.depth, LIT.depth, GLOWS.depth = depth, depth - 0x100, depth - 0x200
    local pts, cols = LIT.points, LIT.colors
    local function light(x, y)
      local dx, dy = x - lx, y - ly
      if dy < 0 then dy = dy * 3 end
      return power / (1 + (dx * dx + dy * dy) / (reach * reach))
    end
    local dark, glows = 0, 0
    for _, puff in ipairs(puffs) do
      local t, size
      if puff.life then
        t = puff.age / puff.life
        size = lerp(t, puff.s0, puff.s1)
      else
        t, size = puff.alpha, puff.size
      end
      t = t * fade
      local x, y, hw, hh = puff.x, puff.y, 64 * size, 40 * size
      pts[1][1], pts[1][2] = x - hw, y - hh
      pts[2][1], pts[2][2] = x + hw, y - hh
      pts[3][1], pts[3][2] = x + hw, y + hh
      pts[4][1], pts[4][2] = x - hw, y + hh
      dark = batch(DARK, dark, pts, colour(255 * t, dark_rgb[1], dark_rgb[2], dark_rgb[3]))
      if power > 0 then
        local lit = 0
        for i = 1, 4 do
          local l = light(x + spread * (pts[i][1] - x), y + spread * (pts[i][2] - y))
          cols[i] = colour(255 * t * math.min(1, 1.5 * l), math.floor(lerp(l, 70, 235)),
            math.floor(lerp(l, 80, 240)), math.floor(lerp(l, 190, 255)))
          lit = lit | cols[i]
        end
        if lit >> 24 > 0 then
          wa.draw.quad(LIT)
          local l = light(x, y)
          if 70 * t * l * l >= 1 then glows = batch(GLOWS, glows, pts, colour(70 * t * l * l, LR, LG, LB)) end
        end
      end
    end
    if dark > 0 then DARK.count = dark // 9; wa.draw.quads(DARK) end
    if glows > 0 then GLOWS.count = glows // 9; wa.draw.quads(GLOWS) end
  end
  gfx = { colour = colour, square = square, glow = glow, point = point, ribbon = ribbon,
    noise_span = noise_span, draw_cloud = draw_cloud, glow_sprite = glow_sprite,
    beam_sprite = beam_sprite, cloud_sprite = cloud_sprite, ELECTRIC_DEPTH = ELECTRIC_DEPTH }
  return gfx
end

-- Draws this bundle's strikes.
local installed
function lightning.setup()
  if installed then return end
  installed = true
  if not (wa.on.draw and wa.draw.ribbon) then return end
  local g = lightning.gfx()
  local colour, square, glow, point, ribbon, noise_span, draw_cloud =
    g.colour, g.square, g.glow, g.point, g.ribbon, g.noise_span, g.draw_cloud
  local glow_sprite, ELECTRIC_DEPTH = g.glow_sprite, g.ELECTRIC_DEPTH
  local function new_shape(s)
    s.noise, s.attach = s.noise or {}, s.attach or {}
    for i = 1, 8 do s.attach[i] = nil end
    noise_span(s.noise, 0, 9, 1.0, 0, 0)
    for _ = 1, 6 do s.attach[1 + math.floor(wa.draw.random() * 8)] = true end
    for i = 0, 5 do
      local off = 2 + wa.draw.random() * 4
      if wa.draw.random() < 0.5 then off = -off end
      noise_span(s.noise, 9 + 9 * i, 9, 0.5, 0, off)
    end
    s.ground = 0.5 + wa.draw.random() * 0.3
    -- Each frame of the bolt flashes anew; now and then one is weaker.
    s.flicker = wa.draw.random() < 0.25 and 0.5 or 0.85 + 0.15 * wa.draw.random()
    s.flicker_x = (wa.draw.random() * 2 - 1) * 25
    s.shape_tick = s.ticks
  end
  -- A bolt's glow: a strip through the bolt's points, cut from the middle
  -- column of the glow sheet (u 0.5), so it follows each bend smoothly.
  local HALO = { sprite = glow_sprite, blend = "add", depth = ELECTRIC_DEPTH, points = {} }
  local function beam(noise, off, divs, width, endwidth, scale, x1, y1, x2, y2, glowalpha)
    if divs < 2 then return end
    local dx, dy = (x2 - x1), (y2 - y1)
    local dd = math.sqrt(dx * dx + dy * dy)
    if dd <= 0 then return end
    dx, dy = dx / dd, dy / dd
    local d = divs - 1
    local halo = HALO.points
    -- Wider than two sections, the strip would fold over itself at a bend.
    local reach = math.min(64, 2 * dd / d)
    for i = #halo, divs + 1, -1 do halo[i] = nil end
    for i = 0, divs - 1 do
      local f = i / d
      local n = noise[off + i] or 0
      local x = lerp(f, x1, x2) + scale * dy * n
      local y = lerp(f, y1, y2) - scale * dx * n
      point(i + 1, x, y, 2 * lerp(f, width, endwidth), f, colour(255, LR, LG, LB))
      local h = halo[i + 1] or {}
      halo[i + 1] = h
      -- A branch's glow starts from nothing where it leaves the bolt.
      local start = (glowalpha < 1 and i == 0) and 0 or 1
      h.x, h.y, h.width, h.u = x, y, reach * (1 - 0.75 * (1 - start)), 0.5
      h.color = colour(255 * glowalpha * (1 - f) * start, LR, LG, LB)
    end
    ribbon(divs)
    wa.draw.ribbon(HALO)
  end
  -- Before the bolt comes down, the cloud now and then lights up inside
  -- for a moment, somewhere else each time.
  local function glimmer(s)
    if s.glimmer_tick ~= s.ticks then
      s.glimmer_tick = s.ticks
      local gl = s.glimmer
      if gl and s.ticks >= gl.till then s.glimmer, gl = nil, nil end
      if gl then
        gl.now = gl.power * (0.4 + 0.6 * wa.draw.random())
      elseif s.delay < 110 and wa.draw.random() < 0.06 then
        local power = 0.35 + 0.3 * wa.draw.random()
        s.glimmer = { x = s.sx + (wa.draw.random() * 2 - 1) * 90, y = s.sy - 5 - wa.draw.random() * 20,
          till = s.ticks + 2 + math.floor(wa.draw.random() * 4), power = power, now = power }
      end
    end
    return s.glimmer
  end
  local QUAD = { points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} } }
  local function draw_strike(s)
    local power = lightning.flash(s)
    if power > 0 then
      local lx, ly = s.sx + 15 * s.dirx + (s.flicker_x or 0), s.sy + 15 * s.diry
      draw_cloud(s.cloud, lx, ly, power, 70, 0.6)
      -- Light comes out under the cloud: a wide, flat glow whose top half
      -- sits behind the dark puffs.
      QUAD.sprite, QUAD.frame, QUAD.blend, QUAD.color, QUAD.depth =
        glow_sprite, 0, "add", colour(160 * power, LR, LG, LB), ELECTRIC_DEPTH
      local q = QUAD.points
      local cx, cy = lx + 20 * s.dirx, ly + 35
      q[1][1], q[1][2] = cx - 150, cy - 75
      q[2][1], q[2][2] = cx + 150, cy - 75
      q[3][1], q[3][2] = cx + 150, cy + 75
      q[4][1], q[4][2] = cx - 150, cy + 75
      wa.draw.quad(QUAD)
    else
      local gl = s.delay >= 8 and glimmer(s)
      if gl then draw_cloud(s.cloud, gl.x, gl.y, gl.now, 40, 0.3) else draw_cloud(s.cloud, 0, 0, 0, 1, 1) end
    end
    for _, p in ipairs(s.sparks) do
      local t = p.age / 50
      glow(p.x, p.y, 13 * (1 - t) + 1, colour(255, LR, LG, LB))
    end
    if s.life <= 0 or s.delay >= 8 then return end
    if not s.noise or (s.delay == 0 and s.shape_tick ~= s.ticks) then new_shape(s) end
    local divs, ex, ey = 9, s.ex, s.ey
    if s.delay > 0 then
      local fr = (8 - s.delay) / 8
      divs = math.floor(9 * fr)
      ex, ey = lerp(fr, s.sx, s.ex), lerp(fr, s.sy, s.ey)
    end
    beam(s.noise, 0, divs, 35, 3, 15, s.sx, s.sy, ex, ey, 1.0)
    local sub, d = 0, divs - 1
    for i = 0, divs - 1 do
      if s.attach[i] and d > 0 then
        local f = i / d
        local x = lerp(f, s.sx, ex) + 10 * s.diry * s.noise[i]
        local y = lerp(f, s.sy, ey) - 10 * s.dirx * s.noise[i]
        beam(s.noise, 9 + 9 * sub, 9, lerp(f, 10, 1), 0.1, 15 * (1 - f), x, y,
          x + s.dirx * 100 * (1 - f), y + s.diry * 100 * (1 - f), 0.5 * (1 - f))
        sub = sub + 1
      end
    end
    if s.delay == 0 and s.hit then glow(s.ex, s.ey, 128 * s.ground, colour(255, LR, LG, LB)) end
  end
  wa.on.draw(function()
    for _, s in ipairs(strikes) do
      draw_strike(s)
    end
  end)
end

return lightning
