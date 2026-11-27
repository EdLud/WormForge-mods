-- PX's sentry turrets, the shared part: planting, sweeping, aiming, firing, damage.

local turret = {}
local turrets = {}
turret.NEUTRAL = 6 -- the side of a sentry no team owns: it targets every team
turret.GREY = 0x9A9A9A -- a neutral sentry's tint
local feet = require("lib/sentry_mask")
local health_label = require("lib/sentry_health")
local electrical = require("lib/electrical")

-- How far past its sensor a sentry still reads a worm's own fields: more than a worm
-- moves in a frame. A sentry with no worm that near reads no worm's fields.
turret.NEAR_SLACK_PX = 100

-- Every worm, read once a frame for every sentry: wa.worms.all()'s list, each one's id,
-- where it is, and whether any is invisible.
local watched = {}
function turret.watch(frame)
  if watched.frame == frame then return watched end
  local list = wa.worms.all()
  local ids, x, y, hidden = {}, {}, {}, false
  for i = 1, #list do
    local w = list[i]
    local id = w.id
    ids[i], x[id], y[id] = id, w.x, w.y
    if w.visible == false then hidden = true end
  end
  watched = { frame = frame, list = list, ids = ids, x = x, y = y, hidden = hidden }
  return watched
end

-- PX's motion test: worm `w` (`id`, at `x`, `y`) moves if it has speed, or isn't where
-- it was in `seen`, the watch of the frame the sentry last looked (nil since its turn
-- began).
function turret.moving(w, id, x, y, seen)
  if w.vx ~= 0 or w.vy ~= 0 then return true end
  local was = seen and seen.x[id]
  return was ~= nil and (was ~= x or seen.y[id] ~= y)
end

-- Whether a worm the watch puts at `x`, `y` is within `reach` of (`cx`, `cy`) on each axis.
function turret.near(x, y, cx, cy, reach)
  local dx, dy = x - cx, y - cy
  return dx <= reach and dx >= -reach and dy <= reach and dy >= -reach
end

-- Whether any worm in `watch` is near (`cx`, `cy`), as `turret.near` measures.
function turret.any_near(watch, cx, cy, reach)
  local xs, ys = watch.x, watch.y
  for _, id in ipairs(watch.ids) do
    if turret.near(xs[id], ys[id], cx, cy, reach) then return true end
  end
  return false
end

-- One sprite drawn many times a frame, for wa.on.draw: a brush and a list of boxes,
-- filled by `put` and drawn at once by `flush`.
local MAX_BOXES = 4096 -- brush:boxes' limit a call
local Batch = {}
Batch.__index = Batch

function turret.batch(sprite, depth, blend)
  return setmetatable({ sprite = sprite, depth = depth, blend = blend or "alpha", list = {}, count = 0 }, Batch)
end

function Batch:flush()
  if self.count == 0 then return end
  if not self.brush then
    self.brush = wa.draw.brush{ sprite = self.sprite, depth = self.depth, blend = self.blend }
  end
  self.brush:boxes(self.list, self.count)
  self.count = 0
end

-- A `w` x `h` box centred on (`x`, `y`), turned `angle` radians clockwise.
function Batch:put(x, y, w, h, angle, frame, color)
  if self.count == MAX_BOXES then self:flush() end
  local i, list = self.count * 7, self.list
  list[i + 1], list[i + 2], list[i + 3], list[i + 4] = x, y, w, h
  list[i + 5], list[i + 6], list[i + 7] = angle, frame, color
  self.count = self.count + 1
end

-- The world the screen shows, widened by `reach` pixels: left, top, right, bottom
-- (nil when there's no view to cull to).
function turret.on_screen(reach)
  local v = wa.world.view and wa.world.view()
  if not v or v.w <= 0 or v.h <= 0 then return nil end
  local zoom = v.zoom > 0 and v.zoom or 1
  local hw, hh = v.w / zoom / 2 + reach, v.h / zoom / 2 + reach
  return v.cx - hw, v.cy - hh, v.cx + hw, v.cy + hh
end

local function electrical_targets()
  local out = {}
  for _, t in ipairs(turrets) do
    for _, id in ipairs(wa.sorted(t.state)) do
      local s = t.state[id]
      if s.body.id == id then
        out[#out + 1] = { id = id, x = s.x, y = s.y - t.capture_up, radius = t.capture_radius, t = t, s = s }
      end
    end
  end
  return out
end

local stun_hook

local function register_electrical()
  if not stun_hook then
    stun_hook = true
    local turn_open = false
    wa.on.turn_end(function() turn_open = false end)
    wa.on.turn_start(function(event)
      if turn_open then return end
      turn_open = true
      local alliance = event and event.worm and event.worm.alliance
      for _, t in ipairs(turrets) do
        for _, id in ipairs(wa.sorted(t.state)) do
          local s = t.state[id]
          if s.body.id == id and s.stun then
            if s.stun <= 0 then
              s.stun = nil
              t.reload(s)
            elseif alliance == s.alliance or s.alliance == turret.NEUTRAL then
              s.stun = s.stun - 1
            end
          end
        end
      end
    end)
  end
  electrical.register({
    kind = "turret",
    targets = electrical_targets,
    zap = function(obj, side)
      if obj.t.state[obj.id] == obj.s then obj.t.electric_zap(obj.s.body, obj.s, side) end
    end,
    strike = function(obj, alliance)
      if obj.t.state[obj.id] == obj.s then obj.t.capture(obj.s.body, obj.s, alliance) end
    end,
  })
end

function turret.on_beam(x0, y0, dx, dy, length)
  local best, entry
  for _, t in ipairs(turrets) do
    for _, id in ipairs(wa.sorted(t.state)) do
      local s = t.state[id]
      if s.body.id == id then
        local cx, cy = s.x - x0, s.y - t.capture_up - y0
        local along = cx * dx + cy * dy
        local miss = cx * cx + cy * cy - along * along
        if miss <= t.capture_radius * t.capture_radius then
          local at = along - math.sqrt(math.max(0, t.capture_radius * t.capture_radius - miss))
          if at > 0 and at < length and (not best or at < best) then
            best, entry = at, { t = t, s = s, body = s.body }
          end
        end
      end
    end
  end
  if best then return x0 + best * dx, y0 + best * dy, entry end
end

function turret.capture_hit(entry, x, y, alliance)
  if not entry or entry.t.state[entry.body.id] ~= entry.s then return false end
  local dx, dy = entry.s.x - x, entry.s.y - entry.t.capture_up - y
  if dx * dx + dy * dy > (entry.t.capture_radius + 6) * (entry.t.capture_radius + 6) then return false end
  return entry.t.capture(entry.body, entry.s, alliance)
end

function turret.projectile_target(x, y)
  for _, t in ipairs(turrets) do
    for _, id in ipairs(wa.sorted(t.state)) do
      local s = t.state[id]
      if s.body.id == id and math.abs(x - s.x) < 20
        and math.abs(y - (s.y - t.capture_up)) < 20 then
        return { t = t, s = s, body = s.body }
      end
    end
  end
end

function turret.projectile_hit(entry, damage, vx, vy, id)
  if entry and entry.t.state[entry.body.id] == entry.s then
    entry.t.projectile_hit(entry.body, entry.s, damage, vx, vy, id)
    return true
  end
  return false
end

local DEFAULTS = {
  sensor_px = 360, -- detection radius
  ammo = 20, -- rounds per turn
  shot_frames = 6, -- frames between rounds
  activate = 60, -- frames after acquiring before the first shot
  beep_frames = 60, -- minimum gap between alert beeps
  rot_idle = 0.5, -- degrees per frame while sweeping
  rot_active = 1.5, -- PX tracking speed, degrees per frame
  sweep = 10, -- PX idle sweep amplitude, degrees
  aim_tolerance = 1.5, -- PX fires only after rotation reaches the target
  require_motion = true, -- PX only acquires walking/jumping/moving worms
  settle_px = 4,
  sink_px = 0,
  foot_offsets = { -6, 7 }, -- support beside the buried mask, never inside it
  top_px = feet.top, -- top of the feet/hub silhouette above its anchor
  capture_radius = 24, -- Lightning's circle around the body
  capture_up = 16 - feet.burial,
  muzzle_up = 25 - feet.burial, -- pixels from the anchor up to the turret pivot
  sight_grace_px = 4,
  placement_reach = 64,
  health = 50,
  slide_friction = 0.20, -- pixels/frame lost on supported ground
  drop_keep = 0.5, -- the share of a flying worm's speed a sentry it drops keeps
  drop_max = 3, -- pixels/frame: the most of that speed it keeps on each axis
  contact_worm = 0.5, -- fraction of incoming worm velocity transferred
  contact_projectile = 0.25, -- PX Javelin transfers a quarter of its velocity
  boom = { damage = 50, id = 100, below = false },
  boom_up = 20 - feet.burial, -- pixels from the anchor up to the death blast
  disable_on_damage = true, -- positive damage disables the sentry for the turn
  hit_by = "all", -- what hits it once planted (`body.hit_by`)
  passage_hit_by = { arrows = true, melee = true, fire = true, dragon_ball = true, blasts = true },
  head_depth = wa.depth.FRONT,
  -- frame calls an idle sentry sleeps through (`a:sleep`), woken at once by a worm coming
  -- near; its head sweeps half a degree a frame, so a longer sleep would show
  sleep_frames = 2,
}

function turret.angle_to(ax, ay, tx, ty)
  local dx = (tx - ax) // 1
  local dy = (ty - ay) // 1
  local deg = math.deg(wa.math.atan(dx, dy))
  if deg < 0 then deg = deg + 360 end
  return deg
end

function turret.muzzle(t, a, angle)
  local rad = math.rad(angle)
  return a.x + wa.math.sin(rad) * t.muzzle_out,
    a.y - t.muzzle_up + wa.math.cos(rad) * t.muzzle_out
end

function turret.trace(a, x0, y0, x1, y1)
  local hit = wa.world.trace { x0 = x0, y0 = y0, x1 = x1, y1 = y1,
    radius = 0, with = { "terrain" }, ignore = { a } }
  if hit and hit.starts_solid then return { hit = true, x = x0, y = y0 } end
  if hit and hit.hit then return hit end
end

function turret.sight(t, a, tx, ty)
  local px, py = a.x, a.y - t.muzzle_up
  local dx, dy = tx - px, ty - py
  local radius = t.muzzle_out + t.sight_grace_px
  local distance2 = dx * dx + dy * dy
  if distance2 <= radius * radius then return true end
  local scale = radius / math.sqrt(distance2)
  return not turret.trace(a, px + dx * scale, py + dy * scale, tx, ty)
end

local function turn_toward(cur, want, speed)
  local d = (want - cur + 540) % 360 - 180
  if d > speed then d = speed elseif d < -speed then d = -speed end
  return (cur + d) % 360
end

-- Frames after a sentry plays a sound in which no sentry plays it again: sentries
-- placed, woken or firing together sound like one, not all of them at once.
local SOUND_GAP_FRAMES = 10
local played = {}

-- Every sentry and turret sound goes through here (a file or WA's sound number).
function turret.play(a, sound)
  if not sound then return end
  local frame = wa.world.frame() or 0
  local last = played[sound]
  if last and frame >= last and frame - last < SOUND_GAP_FRAMES then return end
  played[sound] = frame
  wa.sound.play(a, sound)
end
local play = turret.play

local function angle_gap(a, b)
  local d = (a - b + 540) % 360 - 180
  return d < 0 and -d or d
end

function turret.tint(t, s)
  if s.alliance == turret.NEUTRAL then return turret.GREY end
  return t.tints[s.alliance + 1] or t.tints[1]
end

function turret.new(cfg)
  health_label.install()
  local t = {}
  for k, v in pairs(DEFAULTS) do t[k] = v end
  for k, v in pairs(cfg) do t[k] = v end
  local feet = t.feet or feet
  t.feet = feet
  local state = {}

  -- Tracking speed (%): how fast it turns toward a target and how soon it fires once it has one.
  local base_rot, base_activate = t.rot_active, t.activate
  function t.set_tracking(pct)
    t.rot_active = base_rot * pct / 100
    t.activate = base_activate * 100 // pct
  end

  -- The worms near enough to track, in wa.worms.all()'s order; a far one can't be
  -- tracked, so only the near ones' fields are read.
  local function worm_targets(_, _, s, watch)
    local out = {}
    local cx, cy, reach = s.x, s.y - t.muzzle_up, t.sensor_px + turret.NEAR_SLACK_PX
    local ids, xs, ys = watch.ids, watch.x, watch.y
    for i, w in ipairs(watch.list) do
      local id = ids[i]
      if turret.near(xs[id], ys[id], cx, cy, reach) and w.visible ~= false and w.state ~= "frozen" then
        local x, y = w.x, w.y
        out[#out + 1] = { key = id, x = x, y = y, alliance = w.alliance,
          moving = turret.moving(w, id, x, y, s.seen), obj = w }
      end
    end
    return out
  end
  local targets = cfg.targets or worm_targets

  local function can_track(a, s, c, need_motion)
    if (c.alliance or turret.NEUTRAL) == s.alliance then return false end
    if need_motion and t.require_motion and not c.moving then return false end
    local ex, ey = a.x, a.y - t.muzzle_up
    local dx, dy = (c.x - ex) // 1, (c.y - ey) // 1
    if dx * dx + dy * dy > t.sensor_px * t.sensor_px then return false end
    return turret.sight(t, a, c.x, c.y)
  end

  local function acquire(a, s, list)
    local ex, ey = a.x, a.y - t.muzzle_up
    local best, best_d
    for _, c in ipairs(list) do
      if can_track(a, s, c, true) then
        local dx, dy = (c.x - ex) // 1, (c.y - ey) // 1
        local d = dx * dx + dy * dy
        if not best_d or d < best_d then best, best_d = c, d end
      end
    end
    return best
  end

  local function held(a, s, list)
    if s.tid == nil then return nil end
    for _, c in ipairs(list) do
      if c.key == s.tid then return can_track(a, s, c, false) and c or nil end
    end
    return nil
  end

  function t.start_firing(a, s)
    if s.firing then return end
    s.firing, s.anim = true, 0
    s.cooldown = 0
    s.fire_sound = 35
    play(a, t.sounds.fire_loop)
  end

  function t.stop_firing(a, s)
    if not s.firing then return end
    s.firing, s.anim = false, 0
    play(a, t.sounds.fire_end)
  end

  local function update_servo(a, s, rotating)
    if rotating then
      if not s.rotating then
        s.rotating, s.servo_sound = true, 17
        play(a, t.sounds.servo_start)
      elseif s.servo_sound <= 0 then
        s.servo_sound = 47
        play(a, t.sounds.servo_loop)
      end
    elseif s.rotating then
      s.rotating, s.servo_sound = false, 0
      play(a, t.sounds.servo_end)
    end
  end

  local function count_down(s)
    if s.beep > 0 then s.beep = s.beep - 1 end
    if s.activate > 0 then s.activate = s.activate - 1 end
    if s.cooldown > 0 then s.cooldown = s.cooldown - 1 end
    if s.servo_sound > 0 then s.servo_sound = s.servo_sound - 1 end
    if s.fire_sound > 0 then s.fire_sound = s.fire_sound - 1 end
  end

  -- A frame the sentry slept through, idle: its sweep (or an inactive one's turn to
  -- rest) and its countdowns, as `think` runs them with no target.
  local function slept_frame(s)
    local want = s.idle + s.sweep_dir * t.sweep
    s.angle = turn_toward(s.angle, want, t.rot_idle)
    if s.angle == want then s.sweep_dir = -s.sweep_dir end
    if (180 - s.angle) * s.side < 0 then
      s.side = -s.side
      s.idle = 180 - 90 * s.side
    end
    if not s.active then s.angle = turn_toward(s.angle, s.idle - 45 * s.side, t.rot_idle) end
    count_down(s)
  end

  local function think(a, s, frame, steps)
    for _ = 2, steps do slept_frame(s) end
    local watch = not cfg.targets and turret.watch(frame)

    local target
    if s.active then
      local list = targets(t, a, s, watch)
      target = held(a, s, list)
      if not target and not s.lost then
        target = acquire(a, s, list)
        if target then s.tid = target.key end
      end
    end
    if watch then s.seen = watch end
    local want
    local hx, hy = a.x, a.y - t.muzzle_up
    if target then
      if not s.had_target then
        s.activate = t.activate
        wa.log("Sentry acquired " .. t.kind .. " id=" .. a.id .. " target=" .. target.key
          .. " at=(" .. target.x .. "," .. target.y .. ")")
        if s.beep <= 0 then
          play(a, t.sounds.beep)
          s.beep = t.beep_frames
        end
      end
      s.had_target, s.lost = true, false
      s.tx, s.ty = target.x, target.y
      want = turret.angle_to(hx, hy, target.x, target.y)
      s.angle = turn_toward(s.angle, want, t.rot_active)
    elseif s.had_target then
      if not s.lost then t.stop_firing(a, s) end
      s.lost = true
      want = turret.angle_to(hx, hy, s.tx, s.ty)
      s.angle = turn_toward(s.angle, want, t.rot_active)
      if angle_gap(s.angle, want) <= t.aim_tolerance then
        s.had_target, s.lost, s.tid = false, false, nil
      end
    else
      s.had_target = false
      want = s.idle + s.sweep_dir * t.sweep
      s.angle = turn_toward(s.angle, want, t.rot_idle)
      if s.angle == want then s.sweep_dir = -s.sweep_dir end
    end

    if (180 - s.angle) * s.side < 0 then
      s.side = -s.side
      s.idle = 180 - 90 * s.side
    end

    if not s.active then
      want = s.idle - 45 * s.side
      s.angle = turn_toward(s.angle, want, t.rot_idle)
      t.stop_firing(a, s)
    end

    count_down(s)

    local aligned = target and angle_gap(s.angle, want) <= t.aim_tolerance
    update_servo(a, s, target ~= nil and angle_gap(s.angle, want) >= 2 * t.rot_active)

    local muzzle_clear = false
    if target and s.activate <= 0 and (s.firing or aligned) then
      local mx, my = turret.muzzle(t, a, s.angle)
      muzzle_clear = not turret.trace(a, mx, my, mx, my)
    end
    if muzzle_clear then
      t.start_firing(a, s)
      if s.fire_sound <= 0 then
        s.fire_sound = 35
        play(a, t.sounds.fire_loop)
      end
      if s.cooldown <= 0 then
        t.fire(t, a, s, target)
        s.cooldown = t.shot_frames
      end
    else
      t.stop_firing(a, s)
    end
  end

  function t.owner(a, s)
    local best
    for _, w in ipairs(wa.worms.all()) do
      if w.hp > 0 and w.alliance == s.alliance and (not best or w.id < best.id) then best = w end
    end
    return best or a
  end

  local function disable(a, s)
    s.disabled, s.active = true, false
    s.had_target, s.lost, s.tid = false, false, nil
    t.stop_firing(a, s)
    update_servo(a, s, false)
  end

  local function destroy(a, s, explode)
    state[a.id] = nil
    if explode then
      local owner = t.owner(a, s)
      if owner ~= a then
        wa.world.explode({ x = a.x, y = a.y - t.boom_up, owner = owner,
          damage = t.boom.damage, id = t.boom.id })
      else
        a:explode(t.boom)
      end
    end
    a:remove()
  end

  local function hit(a, ev)
    local s = state[a.id]
    if not s then return end
    if t.ignore_hit and t.ignore_hit(t, a, s, ev) then return end
    local damage = math.max(0, ev.damage or 0)
    if damage > 0 then
      s.health = s.health - damage
      if t.disable_on_damage then disable(a, s) end
      if s.health <= 0 then destroy(a, s, true); return end
    end
    t.push(a, s, ev.vx or 0, ev.vy or 0)
  end

  function t.push(a, s, vx, vy)
    s.vx, s.vy = a.vx + vx, a.vy + vy
    a:warp { x = a.x, y = a.y, vx = s.vx, vy = s.vy }
    if vy < 0 then s.planted = false end
    if vx ~= 0 or vy ~= 0 then t.stop_firing(a, s) end
  end

  local function touched(a, ev)
    local s = state[a.id]
    if not s or not ev.other then return end
    local id = ev.other.id
    if id and s.script_hits[id] then s.script_hits[id] = nil; return end
    if ev.other.kind == "worm" and s.phase ~= 3 then return end
    if ev.other.kind == "actor" then
      for _, other_t in ipairs(turrets) do
        if other_t.state[ev.other.id] then return end
      end
    end
    local fraction = ev.other.kind == "worm" and t.contact_worm or t.contact_projectile
    t.push(a, s, (ev.vx or 0) * fraction, (ev.vy or 0) * fraction)
  end

  function t.projectile_hit(a, s, damage, vx, vy, id)
    if id then s.script_hits[id] = wa.world.frame() end
    hit(a, { damage = damage, vx = vx, vy = vy })
  end

  local function motion(a, s)
    s.x, s.y, s.vx, s.vy = a.x, a.y, a.vx, a.vy
    local planted = s.vy == 0 and a:on_feet()
    if s.planted and not planted then
      t.stop_firing(a, s)
      update_servo(a, s, false)
    end
    if planted and not s.planted then
      s.planted = true
      if not s.landed_once then
        s.landed_once = true
        s.phase = s.planter and 2 or 3
        a.hit_by = s.phase == 3 and t.hit_by or t.passage_hit_by
      end
      play(a, t.sounds.place)
    end
    s.planted = planted
    if s.planted then
      local vx = s.vx
      if math.abs(vx) <= t.slide_friction then vx = 0
      elseif vx > 0 then vx = vx - t.slide_friction
      else vx = vx + t.slide_friction end
      if vx ~= s.vx then
        s.vx = vx
        a.vx = vx
      end
    end
    if a:in_water() then destroy(a, s, false); return false end
    return true
  end

  local brain_think = think
  if cfg.think then brain_think = function(a, s, frame, steps) cfg.think(t, a, s, frame, steps) end end

  -- Nothing to do until a worm comes near: planted and still, no target, not firing.
  local function idle(s)
    return s.planted and not s.planter and s.vx == 0 and s.vy == 0 and s.recoil == 0
      and not (s.firing or s.rotating or s.had_target or s.lost) and s.tid == nil
      and next(s.script_hits) == nil
  end

  -- An idle sentry with no worm near sleeps; the engine wakes it when one comes within
  -- its sensor and the slack (from its body, so the muzzle's height on top), or when it
  -- is hit, touched, moved or lands in water. A sentry aiming at missiles never sleeps.
  local function sleep_if_idle(a, s, frame)
    if cfg.targets or not t.sleep_frames or not a.sleep or not idle(s) then return end
    local reach = t.sensor_px + turret.NEAR_SLACK_PX
    if turret.any_near(turret.watch(frame), s.x, s.y - t.muzzle_up, reach) then return end
    a:sleep(t.sleep_frames, { near = math.ceil(reach + t.muzzle_up) })
  end

  local function brain(a, ev)
    local s = state[a.id]
    if not s then return end
    local steps = 1 + (ev and ev.slept or 0) -- frames since its last call
    s.tick = s.tick + steps
    local frame = wa.world.frame()
    for id, at in pairs(s.script_hits) do
      if at < frame - 1 then s.script_hits[id] = nil end
    end
    if s.recoil > 0 then s.recoil = s.recoil - 1 end
    if s.firing or s.recoil > 0 then s.anim = s.anim + 1 end
    local previous_x, previous_y = s.x, s.y
    if not motion(a, s) then return end
    if s.planter then
      local planter
      for _, w in ipairs(wa.worms.all()) do
        if w.id == s.planter_id and w.hp > 0 then planter = w; break end
      end
      if not planter or (not feet.overlaps_worm(s.x, s.y, planter)
        and not feet.overlaps_worm(previous_x, previous_y, planter)) then
        s.phase, a.hit_by = 3, t.hit_by
        wa.log(string.format("Sentry passage ended %s id=%d planter=%d (%s)",
          t.kind, a.id, s.planter_id, planter and "clear" or "gone"))
        s.planter, s.planter_id = nil, nil
      end
    end
    s.active = not s.disabled and s.ammo > 0
    if s.planted then
      brain_think(a, s, frame, steps)
      if state[a.id] == s then sleep_if_idle(a, s, frame) end
    end
  end

  local function status(s)
    if s.ammo <= 0 then return 0x808080, true, "empty" end
    if not s.planted or not s.active then
      return 0x202020, false, "inactive"
    end
    if s.firing or s.had_target or s.lost or s.recoil > 0 then return 0xFF3030, true, "tracking" end
    return 0x30FF50, true, "ready"
  end
  t.status = status

  local label_clearance = t.art.barrel and 26 or 25

  -- Each sprite's boxes for the frame, drawn in the order the layers were made.
  local layers = {}
  function t.layer(sprite, depth, blend)
    local b = turret.batch(sprite, depth, blend)
    layers[#layers + 1] = b
    return b
  end
  local WHITE = 0xFFFFFFFF
  local BASE, BARREL, GUN, FLARE, LIGHT, LABELS
  if not cfg.draw then
    BASE = t.layer(t.art.base, wa.depth.BEHIND_TERRAIN)
    if t.art.barrel then BARREL = t.layer(t.art.barrel, t.head_depth + 1) end
    GUN = t.layer(t.art.gun, t.head_depth)
    if t.art.flare then FLARE = t.layer(t.art.flare, t.head_depth, "add") end
    LIGHT = t.layer(t.art.light, t.head_depth - 1)
    LABELS = t.layer(health_label.SHEET, t.head_depth - 2)
  end
  local function draw_sentry(s)
    BASE:put(s.x + 1, s.y - 9, 64, 64, 0, 0, WHITE)
    local x, y, angle = s.x, s.y - t.muzzle_up, (90 - s.angle) % 360
    local r = math.rad(angle)
    local pose = (s.firing or s.recoil > 0) and (1 + ((s.anim // 3) % 2)) or 0
    if BARREL then BARREL:put(x, y, 144, 144, r, pose, WHITE) end
    local tint = 0xFF000000 | turret.tint(t, s)
    if t.art.turns then
      -- pre-turned head (tools/bake_turret_rotations.py): the nearest angle's frame, drawn upright;
      -- it is lit per angle, so a laser body needs no mirrored frame facing left
      local turn = math.floor(angle * t.art.turns / 360 + 0.5) % t.art.turns
      local row = t.art.barrel and 0 or pose
      local size = t.art.gun_size or 144
      GUN:put(x, y, size, size, 0, row * t.art.turns + turn, tint)
    else
      GUN:put(x, y, 144, 144, r, t.art.barrel and (s.side < 0 and 1 or 0) or pose, tint)
    end
    if FLARE then FLARE:put(x, y, 144, 144, r, pose == 1 and 1 or 0, WHITE) end
    local rgb, flash = status(s)
    if flash and (s.tick % 30) >= 15 then rgb = (rgb & 0xFEFEFE) >> 1 end
    local lx, ly = -7 * math.cos(r) + 3 * math.sin(r), -7 * math.sin(r) - 3 * math.cos(r)
    LIGHT:put(x + lx, y + ly - 4, 5, 5, 0, 0, 0xFF000000 | rgb)
    health_label.add(LABELS, s.health, s.max_health, x, y - label_clearance + 20)
  end
  local draw = cfg.draw and function(s) cfg.draw(t, s) end or draw_sentry
  local off_screen = cfg.draw_off_screen
  local REACH = 100 -- pixels a sentry's art and label reach past its body
  if wa.on.draw then
    wa.on.draw(function()
      if next(state) == nil then return end
      -- only the sentries the screen shows
      local left, top, right, bottom = turret.on_screen(REACH)
      for id, s in pairs(state) do
        local x, y = s.x, s.y
        if (not left or (x >= left and x <= right and y >= top and y <= bottom)
            or (off_screen and off_screen(s))) and s.body.id == id then
          draw(s)
        end
      end
      for _, b in ipairs(layers) do b:flush() end
    end)
  end

  function t.capture(a, s, alliance)
    if alliance < 0 or alliance > 5 then return false end
    s.alliance = alliance
    if not t.capture_keeps_firing then disable(a, s) end
    return true
  end

  function t.electric_zap(a, s, side)
    if t.tazer == "stun" then
      s.stun = 2
      disable(a, s)
    elseif t.tazer == "empty" then
      s.ammo = 0
    end
    hit(a, { damage = 12, vx = side * 1.2, vy = -4 })
  end

  local function placement(worm, facing)
    local wx, wy, planter_id = worm.x, worm.y, worm.id
    local x, y = wx, wy - feet.burial
    local worms, obstacles, land = {}, {}, {}
    for _, w in ipairs(wa.worms.all()) do
      local id, hp = w.id, w.hp
      if id ~= planter_id and hp > 0 then
        worms[#worms + 1] = { id = id, hp = hp, x = w.x, y = w.y }
      end
    end
    for _, other_t in ipairs(turrets) do
      for _, id in ipairs(wa.sorted(other_t.state)) do
        local other = other_t.state[id]
        if (other.landed_once or other.phase == 3) and other.body.id == id then
          obstacles[#obstacles + 1] = { x = other.body.x, y = other.body.y, feet = other_t.feet }
        end
      end
    end
    local function solid(px, py)
      local row = land[py]
      if not row then row = {}; land[py] = row end
      local value = row[px]
      if value == nil then value = wa.land.solid(px, py); row[px] = value end
      return value
    end
    for radius = 0, t.placement_reach, 4 do
      local step = radius == 0 and 360 or math.max(15, math.floor(360 / (radius / 2)))
      for deg = 0, 359, step do
        local angle = math.rad(deg)
        local tx = x + facing * radius * wa.math.cos(angle)
        local ty = y + radius * wa.math.sin(angle)
        local blocked = false
        for _, other in ipairs(obstacles) do
          if feet.intersects(tx, ty, other.x, other.y, other.feet) then blocked = true; break end
        end
        if not blocked and feet.clear(tx, ty, worms, planter_id, 0, solid) then
          local hit = wa.land.trace(wx, wy - 8, tx, ty - feet.top / 2)
          if not hit or not hit.hit then return tx, ty end
        end
      end
    end
  end

  -- Part of a worm's speed on one axis, for a sentry it drops from a vehicle.
  local function kept(v)
    v = v * t.drop_keep
    return math.max(-t.drop_max, math.min(t.drop_max, v))
  end

  -- What a worm drops a sentry from: a vehicle, a tool or a jump. On its feet it plants
  -- it still, however it moves.
  local FLYING = { jetpacking = true, parachuting = true, roping = true, bungee = true,
    jumping = true, jump_falling = true, falling = true }

  -- A sentry body at x, y (its feet's bottom), moving at vx, vy; a planter worm passes
  -- through it until clear.
  local function spawn(x, y, owner, alliance, facing, planter, vx, vy)
    local idle = facing < 0 and 270 or 90
    local body = wa.actors.spawn({
      sprite = false, x = x, y = y,
      vx = vx or 0, vy = vy or 0,
      origin = "bottom", owner = owner, persist = true,
      gravity = 1, body = { shape = t.art.mask, hits = { land = true, objects = true },
        hit_by = { fire = true, dragon_ball = true, blasts = true } },
      on = { frame = brain, hit = hit, touched = touched },
    })
    local s = {
      alliance = alliance, planted = false, active = true, disabled = false, ammo = t.ammo,
      x = x, y = y, vx = body.vx, vy = body.vy, tick = 0,
      script_hits = {}, health = t.health, max_health = t.health,
      angle = idle, idle = idle, side = facing < 0 and -1 or 1,
      sweep_dir = 1, shots = 0, firing = false, anim = 0, rotating = false,
      servo_sound = 0, fire_sound = 0, beep = 0, activate = 0, cooldown = 0,
      had_target = false, lost = false, recoil = 0,
      planter = planter, planter_id = planter and planter.id,
      landed_once = false, phase = 1,
    }
    state[body.id] = s
    s.body = body
    if t.init then t.init(t, body, s) end
    return body, s
  end

  function t.place(fire_ev)
    local worm = fire_ev.worm
    local alliance = worm.alliance or 0
    if alliance < 0 or alliance > 5 then alliance = 0 end
    local facing = worm.facing
    local x, y = placement(worm, facing)
    if not x then
      local ammo = worm:ammo(t.weapon)
      if ammo >= 0 then worm:ammo(t.weapon, { set = ammo + 1 }) end
      wa.log("Sentry: no clear placement within " .. t.placement_reach .. "px; charge refunded")
      return nil
    end
    -- dropped from a vehicle, it keeps some of the worm's speed
    local vx, vy = 0, 0
    if worm.taken or FLYING[worm.state] then vx, vy = kept(worm.vx or 0), kept(worm.vy or 0) end
    local body, s = spawn(x, y, worm, alliance, facing, worm, vx, vy)
    wa.log(string.format("Sentry placed %s id=%d planter=%d at=(%.2f,%.2f) v=(%.2f,%.2f) passage=on",
      t.kind, body.id, worm.id, x, y, vx, vy))
    return body, s
  end

  -- A neutral sentry no team owns, dropped at x, y.
  function t.spawn_neutral(x, y, facing)
    local body, s = spawn(x, y, "none", turret.NEUTRAL, facing)
    wa.log(string.format("Sentry spawned %s id=%d at=(%.2f,%.2f) neutral", t.kind, body.id, x, y))
    return body, s
  end

  wa.on.turn_end(function(ev)
    local worm = ev.worm
    if not worm then return end
    for _, id in ipairs(wa.sorted(state)) do
      local s = state[id]
      if s.body.id == id and s.planter_id == worm.id then
        s.planter, s.planter_id = nil, nil
        s.phase, s.body.hit_by = 3, "all"
      end
    end
  end)

  local function reload(s)
    s.ammo, s.active, s.disabled, s.had_target, s.tid, s.lost, s.seen = t.ammo, true, false, false, nil, false, nil
    if t.turn_begin then t.turn_begin(t, s) end
  end

  wa.on.worm_message(function(_, msg)
    if msg ~= wa.msg.START_TURN then return end
    for id, s in pairs(state) do
      if s.body.id ~= id then state[id] = nil
      elseif s.stun then
        s.active, s.disabled, s.had_target, s.tid, s.lost, s.seen = false, true, false, nil, false, nil
      else
        reload(s)
      end
    end
  end, { msgs = { wa.msg.START_TURN } })

  t.reload = reload

  t.state = state -- for the Highlander mock
  turrets[#turrets + 1] = t
  register_electrical()
  return t
end

return turret
