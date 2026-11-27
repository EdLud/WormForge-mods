-- PyroMan's turrets on lib/turret.lua's body: planting, health, capture, death blast.

local turret = require("lib/turret")
local mask = require("lib/sentry_mask")
local health_label = require("lib/sentry_health")

local pyro = {}

local ART = "sprites/pyro_turrets/"
local SND = "sounds/pyro_turrets/"
pyro.SHEET = ART .. "turrets.png"
pyro.AMMO_PETROL = ART .. "ammo_petrol.png"
pyro.AMMO_FLAME = ART .. "ammo_flame.png"
local AIM_SOUND, SETUP_SOUND = SND .. "turret_aim.wav", SND .. "turret_setup.wav"

pyro.FRAMES = {
  mine = { head = 0, base = 1 },
  petrol = { head = 2, base = 3 },
  ballista = { head = 4, base = 5 },
  flame = { head = 6, base = 8 },
}
local MIRROR, RETICLE = 14, 13

local R = 9
local rows = {}
for dy = -2 * R, 0 do
  local d, half = dy + R, 0
  while (half + 1) * (half + 1) + d * d <= R * R do half = half + 1 end
  rows[#rows + 1] = { dy, -half, half }
end
pyro.feet = mask.build(rows, 2 * R, -R, R, 0)

local Z_AMMO, Z_HEAD, Z_BASE = 0xA0000, 0xB0000, 0xC0000

local FRAME_MS = 20 -- WA's 50 frames a second

local TINTS = { 0xFF8080, 0x8080FF, 0x80FF80, 0xE6E680, 0xE680E6, 0x80E6E6 }

local BASE = {
  tower_offset = 25, -- pixels from the centre up to the head's pivot
  tower_len = 10, -- from the pivot to the muzzle
  g_factor = 1, -- the gravity its aim assumes
  thinking = 15, -- frames between finding a worm and aiming
  min_px = 40, sensor_px = 350, lost_px = 450,
  speed = 0.08, -- radians a frame the head turns
  sleep_frames = 25, -- an idle turret's head stands still, so it sleeps longer (lib/turret)
  fire_rate_ms = 400,
  fire_increase_pct = 12, -- how much longer each next wait is
  aim_sound_gap = 180,
  health = 50, explode_damage = 50,
  aim_ahead = false, -- aim where a moving target will be when the shot lands
}
local PICK_PCT = 30 -- the chance a frame of taking a moving worm in range

local installed = false
function pyro.install()
  if installed then return end
  installed = true
  wa.assets.load({ sprites = { pyro.SHEET, pyro.AMMO_PETROL, pyro.AMMO_FLAME },
    sounds = { AIM_SOUND, SETUP_SOUND } })
end

local function centre(a) return a.x, a.y - R end

local function worm_by_id(watch, id)
  for i, w in ipairs(watch.list) do
    if watch.ids[i] == id then return w end
  end
end

-- PX's pick: each moving enemy worm in range, in wa.worms.all()'s order, a 30% chance;
-- an invisible one ends the search. Only the near worms are read, all of them while one
-- is invisible. `seen` is the watch of the frame this turret last looked.
local function find_target(t, a, s, watch, seen)
  local cx, cy = centre(a)
  local py = cy - t.tower_offset
  local reach = t.sensor_px + turret.NEAR_SLACK_PX
  local ids, xs, ys, all = watch.ids, watch.x, watch.y, watch.hidden
  for i, w in ipairs(watch.list) do
    local id = ids[i]
    if all or turret.near(xs[id], ys[id], cx, py, reach) then
      local x, y = w.x, w.y
      if w.alliance ~= s.alliance and turret.moving(w, id, x, y, seen) and w.hp > 0 and w.state ~= "frozen" then
        if w.visible == false then break end
        local dx, dy = x - cx, y - py
        local d = math.sqrt(dx * dx + dy * dy)
        if d >= t.min_px and d < t.sensor_px and wa.random(0, 99) < t.pick_pct then s.tid = id end
      end
    end
  end
end

local function solve(t, a, s, tx, ty)
  local cx, cy = centre(a)
  local tm = s.flight
  local rx = (tx - cx) / tm
  local y = ty - (cy - t.tower_offset)
  local g = wa.world.gravity() * t.g_factor
  local ry = (2 * y - g * tm * tm) / (2 * tm)
  if rx > 0 then
    s.want, s.dir = wa.math.atan(rx, -ry), 1
  else
    s.want, s.dir = wa.math.atan(-rx, -ry), -1
  end
  s.power = math.sqrt(rx * rx + ry * ry)
  s.lrx, s.lry = rx, ry
end

local function aim(t, a, s, target)
  local cx, cy = centre(a)
  local dx, dy = target.x - cx, target.y - cy
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist > t.lost_px then s.tid = nil; return false end
  if t.aim_time then s.flight = t.aim_time(dist) end
  local tx, ty = target.x, target.y
  if t.aim_ahead then
    tx, ty = tx + target.vx * s.flight, ty + target.vy * s.flight
    if t.aim_time then
      local lx, ly = tx - cx, ty - cy
      s.flight = t.aim_time(math.sqrt(lx * lx + ly * ly))
    end
  end
  solve(t, a, s, tx, ty)
  if math.abs(s.want - s.ta) > t.speed * 2 then
    if s.want > s.ta then s.ta = s.ta + t.speed else s.ta = s.ta - t.speed end
    return false
  end
  s.ta = s.want
  return true
end

local function next_flight(s)
  s.flight = (s.flight + 10) * 1.1
  if s.flight > 100 then s.flight = 16 end
end

local function blocked(t, a, s)
  local x, y = centre(a)
  y = y - t.tower_offset
  local vx, vy = s.lrx, s.lry
  local g = wa.world.gravity() * t.g_factor
  for _ = 1, math.floor(s.flight - 1) do
    if wa.world.collides({ x = x, y = y, radius = 3, with = { "terrain" }, ignore = { a } }) then
      return true
    end
    x, y, vy = x + vx, y + vy, vy + g
  end
  return false
end

function pyro.muzzle_clear(a, shot)
  return not wa.world.collides({ x = shot.x, y = shot.y, radius = 3,
    with = { "terrain", "worms", "mines", "crates", "oil", "graves" }, ignore = { a } })
end

function pyro.force(s)
  return s.power - 0.1 + wa.random(0, 63) / 96
end

local function think(t, a, s, frame, steps)
  local watch, seen = turret.watch(frame), s.seen
  s.seen = watch
  if s.reload > 0 then s.reload = math.max(0, s.reload - FRAME_MS * steps) end
  local target = s.tid and worm_by_id(watch, s.tid)
  if target and target.state == "frozen" then target = nil end
  if s.tid and not target then s.tid = nil end
  if s.draw_aim and target then
    if s.aim_x < target.x then s.aim_x = s.aim_x + 4 elseif s.aim_x > target.x then s.aim_x = s.aim_x - 4 end
    if s.aim_y < target.y then s.aim_y = s.aim_y + 4 elseif s.aim_y > target.y then s.aim_y = s.aim_y - 4 end
  end
  local clock = wa.world.turn_clock()
  local running = s.clock ~= nil and clock < s.clock
  s.clock = clock
  if not running or s.ammo <= 0 or s.disabled then return end
  if s.aim_sound > 0 then s.aim_sound = math.max(0, s.aim_sound - steps) end
  if not target then
    find_target(t, a, s, watch, seen)
    s.wait = t.thinking
    return
  end
  if s.wait > 0 then s.wait = s.wait - 1; return end
  if not aim(t, a, s, target) or s.reload > 0 then return end
  if blocked(t, a, s) then
    if wa.random(0, 99) < 65 then
      next_flight(s)
      s.wait = 4
    else
      s.tid, s.wait = nil, 10
      return
    end
    s.reload = s.reload_time
    return
  end
  local sn, cs = wa.math.sin(s.ta), wa.math.cos(s.ta)
  local cx, cy = centre(a)
  local shot = { x = cx + sn * s.dir * t.tower_len, y = cy - t.tower_offset - cs * t.tower_len,
    dx = sn * s.dir, dy = -cs }
  next_flight(s)
  if t.shoot(t, a, s, shot) then
    s.draw_aim = true
    s.reload = s.reload_time
    s.reload_time = s.reload_time + s.reload_time * t.fire_increase_pct // 100 // FRAME_MS * FRAME_MS
    s.ammo = s.ammo - 1
    if s.aim_sound <= 0 then
      turret.play(a, AIM_SOUND)
      s.aim_sound = t.aim_sound_gap
    end
  else
    s.tid, s.wait = nil, 10
  end
end

local function init(t, a, s)
  local cx, cy = centre(a)
  s.ammo, s.ta, s.dir, s.want, s.power = 0, 1.57, 1, 1.57, 0
  s.reload, s.reload_time, s.flight, s.wait = 0, t.fire_rate_ms, 32, 0
  s.aim_sound, s.draw_aim, s.aim_x, s.aim_y = 0, false, cx, cy
  s.lrx, s.lry = 0, 0
end

local function turn_begin(t, s)
  s.draw_aim, s.aim_x, s.aim_y = false, s.x, s.y - R
  s.reload_time = t.fire_rate_ms
end

local function ignore_hit(t, a, s, hit)
  if hit.kind ~= "arrow" then return false end
  if not hit.team or hit.team == 0 then return s.alliance == turret.NEUTRAL end -- a neutral turret's arrow
  for _, w in ipairs(wa.worms.all()) do
    if w.team == hit.team then return w.alliance == s.alliance end
  end
  return false
end

local function dim(rgb, k)
  local r, g, b = (rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF
  return (math.floor(r * k) << 16) | (math.floor(g * k) << 8) | math.floor(b * k)
end

local SIZE = 40 -- the sheet's frames, pixels square

local function draw(t, s)
  local layers = t.pyro_layers
  local cx, cy = s.x, s.y - R
  local rgb = turret.tint(t, s)
  local colour = 0xFF000000 | rgb
  layers.base:put(cx, cy, SIZE, SIZE, 0, t.frames.base, colour)
  if s.draw_aim and s.tid then
    layers.base:put(s.aim_x, s.aim_y, SIZE, SIZE, wa.world.frame() * 0.04, RETICLE, colour)
  end
  local head = 0xFF000000 | dim(rgb, math.max(0, s.health) / s.max_health * 0.75 + 0.25)
  if layers.ammo then
    local size = t.ammo_size or SIZE
    layers.ammo:put(cx, cy, size, size, 0, 0, head)
  end
  local frame, rot = t.frames.head, s.ta - 1.5707
  if s.dir < 0 then frame, rot = frame + MIRROR, 1.5707 - s.ta end
  local py = cy - t.tower_offset
  layers.head:put(cx, py, SIZE, SIZE, rot, frame, head)
  health_label.add(layers.labels, s.health, s.max_health, cx, py - 10)
end

-- Its reticle shows while it aims, wherever the turret is.
local function draw_off_screen(s) return s.draw_aim and s.tid ~= nil end

function pyro.set_options(t, option)
  t.health, t.ammo = option("health"), option("ammo")
  t.fire_rate_ms, t.fire_increase_pct = option("fire_rate"), option("fire_increase_pct")
  t.set_tracking(option("tracking_pct"))
  t.aim_ahead = option("aim_ahead")
end

function pyro.configure(t, ctx)
  pyro.set_options(t, ctx.option)
end

function pyro.new(cfg)
  pyro.install()
  local c = {}
  for k, v in pairs(BASE) do c[k] = v end
  for k, v in pairs(cfg) do c[k] = v end
  c.feet = pyro.feet
  c.muzzle_up, c.muzzle_out = R + c.tower_offset, c.tower_len
  c.capture_up, c.capture_radius = R + 4, 16
  c.boom_up = R
  c.boom = { damage = c.explode_damage, id = 100, below = false }
  c.disable_on_damage = false
  c.capture_keeps_firing = true
  c.art = { mask = ART .. "mask.png" }
  c.sounds = { place = SETUP_SOUND }
  c.tints = TINTS
  c.think, c.draw, c.init, c.turn_begin, c.ignore_hit = think, draw, init, turn_begin, ignore_hit
  c.draw_off_screen = draw_off_screen
  local t = turret.new(c)
  t.pyro_layers = { -- in PX's order: base and reticle, ammo, head, label
    base = t.layer(pyro.SHEET, Z_BASE),
    ammo = c.ammo_sprite and t.layer(c.ammo_sprite, Z_AMMO),
    head = t.layer(pyro.SHEET, Z_HEAD),
    labels = t.layer(health_label.SHEET, Z_AMMO - 1),
  }
  local base_speed, base_thinking = t.speed, t.thinking
  t.pick_pct = PICK_PCT
  function t.set_tracking(pct) -- faster turning, less thinking, a likelier pick
    t.speed = base_speed * pct / 100
    t.thinking = base_thinking * 100 // pct
    t.pick_pct = math.min(100, PICK_PCT * pct // 100)
  end
  return t
end

return pyro
