-- Highlander: Project X's sentry turrets (weapon_sentry_gun's PxSentryGun,
-- weapon_sentry_laser's PxSentryLaser), the part they share: a body dropped
-- in front of the worm that falls and plants itself, a head that sweeps,
-- picks the nearest moving enemy it can see, turns to it and fires, reloads
-- each turn, and is disabled for the turn by a blast and explodes at 0
-- health. What it aims at and what it fires are the weapon's: `targets` (by
-- default the worms) and `fire(t, a, s, target)`.
--
-- From the standalone sentry_gun port (mods/examples/sentry_gun_old), with
-- its numbers as the defaults. Angles: 0 down, 90 right, 180 up, 270 left.
local turret = {}

local DEFAULTS = {
  sensor_px = 360,      -- detection radius
  ammo = 20,            -- rounds per turn
  shot_frames = 6,      -- frames between rounds
  activate = 60,        -- frames after acquiring before the first shot
  beep_frames = 60,     -- minimum gap between alert beeps
  rot_idle = 0.5,       -- degrees per frame while sweeping
  rot_active = 1.5,     -- PX tracking speed, degrees per frame
  sweep = 10,           -- PX idle sweep amplitude, degrees
  aim_tolerance = 1.5,  -- PX fires only after rotation reaches the target
  require_motion = true, -- PX only acquires walking/jumping/moving worms
  hold_own_turn = true, -- the Sentry Gun holds fire on its colour's turns
  sink_px = 8,          -- pixels the planted turret settles into the ground
  muzzle_up = 25,       -- pixels from the anchor up to the turret pivot
  front_px = 5,         -- the body lands this far in front of the worm
  health = 50,
  boom = { damage = 50, id = 100, below = false },
  -- Occlusion band for the head: in front of terrain (0x180000), so the
  -- landscape never buries it.
  head_depth = wa.depth.FRONT,
}

-- 0 = down, 90 = right: the art faces right, and screen y grows down.
-- wa.math: an aim reaches the simulation (what the turret sees and hits), so
-- it must come out the same on every machine.
function turret.angle_to(ax, ay, tx, ty)
  local dx = (tx - ax) // 1
  local dy = (ty - ay) // 1
  local deg = math.deg(wa.math.atan(dx, dy))
  if deg < 0 then deg = deg + 360 end
  return deg
end

local function turn_toward(cur, want, speed)
  local d = (want - cur + 540) % 360 - 180
  if d > speed then d = speed elseif d < -speed then d = -speed end
  return (cur + d) % 360
end

-- A turret without one of the sounds (the laser has no firing loop) skips it.
local function play(a, sound)
  if sound then a:sound(sound) end
end

local function angle_gap(a, b)
  local d = (a - b + 540) % 360 - 180
  return d < 0 and -d or d
end

-- `cfg`: the weapon's numbers (over DEFAULTS), `art` { base, gun, flare,
-- barrel }, `sounds` { place, beep, fire_loop, fire_end, servo_start,
-- servo_loop, servo_end }, `tints` (team colours, red to cyan, 0xRRGGBB),
-- `kind`, `fire(t, a, s, target)`, which shoots once (a, the body; s, its
-- state), and optionally `targets(t, a, s)`, what it can aim at: a list of
-- { key, x, y, alliance, moving }, in an order the same on every machine.
-- Returns `t`, whose `place(fire_ev)` drops a turret for the firing worm.
--
-- The head: `gun`, team-tinted, its frames the firing poses; with a
-- `barrel`, the barrel is its own untinted layer behind it, its frames the
-- poses, and the gun's two frames are its art and its mirror image, for a
-- turret that has turned to face left (PX draws it flipped).
function turret.new(cfg)
  local t = {}
  for k, v in pairs(DEFAULTS) do t[k] = v end
  for k, v in pairs(cfg) do t[k] = v end
  local state = {}
  -- The colour taking its turn: its turrets hold fire. Alliance, not team:
  -- it is WA's colour index (0 red .. 5 cyan), shared by allied teams.
  local active_alliance = nil

  local function note_motion(s, w)
    local p = s.seen[w.id]
    local m = (w.vx ~= 0 or w.vy ~= 0)
    if p then
      if p.x ~= w.x or p.y ~= w.y then m = true end
      p.x, p.y, p.moving = w.x, w.y, m
    else
      s.seen[w.id] = { x = w.x, y = w.y, moving = m }
    end
  end

  -- The Sentry Gun's targets: the worms, keyed by worm id; moving by
  -- note_motion.
  local function worm_targets(_, _, s)
    local out = {}
    for _, w in ipairs(wa.worms.all()) do
      if w.visible ~= false then
      local p = s.seen[w.id]
        out[#out + 1] = { key = w.id, x = w.x, y = w.y, alliance = w.alliance, moving = p and p.moving, obj = w }
    end
    end
    return out
  end
  local targets = cfg.targets or worm_targets

  -- PX needs movement to notice a target, but keeps an acquired one on line
  -- of sight alone. Seen from the head, not the feet on the ground.
  local function sees(a, s, c, need_motion)
    if c.alliance == s.alliance then return false end
    if need_motion and t.require_motion and not c.moving then return false end
    local ex, ey = a.x, a.y - t.muzzle_up
    local dx, dy = (c.x - ex) // 1, (c.y - ey) // 1
    if dx * dx + dy * dy > t.sensor_px * t.sensor_px then return false end
    return not wa.land.trace(ex, ey, c.x, c.y)
  end

  -- The nearest moving enemy in sight; ties to the first listed, the same
  -- everywhere.
  local function acquire(a, s, list)
    local ex, ey = a.x, a.y - t.muzzle_up
    local best, best_d
    for _, c in ipairs(list) do
      if sees(a, s, c, true) then
        local dx, dy = (c.x - ex) // 1, (c.y - ey) // 1
        local d = dx * dx + dy * dy
        if not best_d or d < best_d then best, best_d = c, d end
      end
    end
    return best
  end

  -- PX keeps its target until it loses sight of it.
  local function held(a, s, list)
    if s.tid == nil then return nil end
    for _, c in ipairs(list) do
      if c.key == s.tid then return sees(a, s, c, false) and c or nil end
    end
    return nil
  end

  function t.start_firing(a, s)
    if s.firing then return end
    s.firing, s.anim = true, 0
    -- PX zeroes ShootTimer as firing (re)starts: the first round goes now.
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

  local function think(a, s)
    -- A planted turret is immovable: blasts would otherwise add up.
    if s.px then a.x, a.y = s.px, s.py end
    a.vx, a.vy = 0, 0
    if not cfg.targets then
    for _, w in ipairs(wa.worms.all()) do note_motion(s, w) end
    end

    local target
    if s.active then
      local list = targets(t, a, s)
      target = held(a, s, list)
      if not target and not s.lost then
        target = acquire(a, s, list)
        if target then s.tid = target.key end
      end
    end
    local want
    local hx, hy = a.x, a.y - t.muzzle_up
    if target then
      if not s.had_target then
        s.activate = t.activate
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
      -- PX stops firing at once, turns to the last place it saw it, then
      -- drops it.
      if not s.lost then t.stop_firing(a, s) end
      s.lost = true
      want = turret.angle_to(hx, hy, s.tx, s.ty)
      s.angle = turn_toward(s.angle, want, t.rot_active)
      if angle_gap(s.angle, want) <= t.aim_tolerance then
        s.had_target, s.lost, s.tid = false, false, nil
      end
    else
      -- PX sweeps to one side and turns back the moment it gets there.
      s.had_target = false
      want = s.idle + s.sweep_dir * t.sweep
      s.angle = turn_toward(s.angle, want, t.rot_idle)
      if s.angle == want then s.sweep_dir = -s.sweep_dir end
    end

    -- PX: turned over itself, it idles facing the other way.
    if (180 - s.angle) * s.side < 0 then
      s.side = -s.side
      s.idle = 180 - 90 * s.side
    end

    if not s.active then
      want = s.idle - 45 * s.side
      s.angle = turn_toward(s.angle, want, t.rot_idle)
      t.stop_firing(a, s)
    end

    if s.beep > 0 then s.beep = s.beep - 1 end
    if s.activate > 0 then s.activate = s.activate - 1 end
    if s.cooldown > 0 then s.cooldown = s.cooldown - 1 end
    if s.servo_sound > 0 then s.servo_sound = s.servo_sound - 1 end
    if s.fire_sound > 0 then s.fire_sound = s.fire_sound - 1 end

    local aligned = target and angle_gap(s.angle, want) <= t.aim_tolerance
    -- PX's long-rotation sound: a turn left of at least twice its speed.
    update_servo(a, s, target ~= nil and angle_gap(s.angle, want) >= 2 * t.rot_active)

    -- PX latches firing once on target, until it loses it, runs dry or is
    -- disabled.
    local hold_fire = t.hold_own_turn and active_alliance == s.alliance
    if target and not hold_fire and s.activate <= 0 and (s.firing or aligned) then
      t.start_firing(a, s)
      if s.fire_sound <= 0 then
        s.fire_sound = 35
        play(a, t.sounds.fire_loop)
      end
      if s.cooldown <= 0 then
        t.fire(t, a, s, target)
        s.cooldown = t.shot_frames
      end
    elseif not target or hold_fire then
      t.stop_firing(a, s)
    end
  end

  -- The body is the actor; the head and its flare ride on it, drawn only.
  local function sync(a, s)
    local gun = s.gun
    if not gun or gun.dead then return end
    gun.x, gun.y, gun.vx, gun.vy = a.x, a.y - t.muzzle_up, 0, 0
    local pose = (s.firing or s.recoil > 0) and (1 + ((s.anim // 3) % 2)) or 0
    local barrel = s.barrel
    -- With a barrel layer, the gun's frames are its art and its mirror.
    local look = barrel and (s.side < 0 and 1 or 0) or pose
    if look ~= s.look then
      gun:frame(look)
      s.look = look
    end
    if barrel and not barrel.dead then
      barrel.x, barrel.y, barrel.vx, barrel.vy = gun.x, gun.y, 0, 0
      if pose ~= s.pose then barrel:frame(pose) end
      barrel:gfx({ angle = (90 - s.angle) % 360, tint = 0xFFFFFF, depth = t.head_depth + 1 })
    end
    s.pose = pose
    local flare = s.flare
    if flare and not flare.dead then
      flare.x, flare.y, flare.vx, flare.vy = gun.x, gun.y, 0, 0
      local lit = (pose == 1) and 1 or 0
      if lit ~= s.lit then
        flare:frame(lit)
        s.lit = lit
      end
      flare:gfx({ angle = (90 - s.angle) % 360, tint = 0xFFFFFF, blend = "add", depth = t.head_depth })
    end
    -- The head art faces right; the renderer takes clockwise screen degrees.
    gun:gfx({ angle = (90 - s.angle) % 360, tint = t.tints[s.alliance + 1] or t.tints[1], depth = t.head_depth })
  end

  local function remove(s)
    if s.gun and not s.gun.dead then s.gun:despawn() end
    if s.flare and not s.flare.dead then s.flare:despawn() end
    if s.barrel and not s.barrel.dead then s.barrel:despawn() end
  end

  local function brain(a, ev)
    local s = state[a.id]
    if not s then return end
    ev = ev or {}
    if (ev.damage or 0) > 0 then
      s.health = s.health - ev.damage
      s.active = false
      t.stop_firing(a, s)
      update_servo(a, s, false)
      if s.health <= 0 then
        remove(s)
        state[a.id] = nil
        -- PX explodes at PosY-20: the body, not the feet.
        a:explode(t.boom)
        a:despawn()
        return
      end
    end
    -- `recoil`: frames the firing pose lingers after a shot the weapon ended
    -- at once (the laser's).
    if s.recoil > 0 then s.recoil = s.recoil - 1 end
    if s.firing or s.recoil > 0 then s.anim = s.anim + 1 end

    if not s.planted then
      a:gravity()
      local hit = a:move({ terrain = true, worms = false })
      if hit.land then
        a.vx, a.vy = 0, 0
        s.planted = true
        s.px, s.py = a.x, a.y + t.sink_px
        play(a, t.sounds.place)
        sync(a, s)
        return
      end
      a:advance()
      if a:in_water() then
        remove(s)
        state[a.id] = nil
        a:despawn()
        return
      end
    else
      think(a, s)
    end
    sync(a, s)
  end

  -- Who owns what the turret fires: the worm that placed it, as WA lists it
  -- now, else the turret itself. The handle kept from the placing names WA's
  -- freed worm once that worm has died, and a spawn refuses such an owner.
  function t.owner(a, s)
    for _, w in ipairs(wa.worms.all()) do
      if w.id == s.owner_id then return w end
    end
    return a
  end

  -- Slightly in front of the worm, unless a wall is that close.
  local function placement_x(worm, facing)
    local x = worm.x + facing * t.front_px
    if wa.land.trace(worm.x, worm.y, x, worm.y) then return worm.x end
    return x
  end

  local function rider(sheet, x, y, worm, kind)
    return wa.actors.spawn({
      sprite = sheet, x = x, y = y, vx = 0, vy = 0, gravity = false, collide = false,
      loop = false, origin = "center", owner = worm, kind = kind, persist = true,
      on = function() end,
    })
  end

  -- Drop a turret for the firing worm, its owner's colour (not worm.team,
  -- its roster slot: online a blue team in slot 1 placed a red turret).
  function t.place(fire_ev)
    local worm = fire_ev.worm
    local alliance = worm.alliance or 0
    if alliance < 0 or alliance > 5 then alliance = 0 end
    local facing = worm.facing
    local idle = facing < 0 and 270 or 90
    local x = placement_x(worm, facing)
    local body = wa.actors.spawn({
      sprite = t.art.base, x = x, y = worm.y,
      -- A small nudge, whatever the aim or charge.
      vx = (worm.vx / 2) + facing * 0.3000030517578125, vy = (worm.vy / 2) - 0.149993896484375,
      loop = false, origin = "bottom", owner = worm, kind = t.kind, persist = true, on = brain,
    })
    local s = {
      alliance = alliance, owner = worm, owner_id = worm.id, planted = false, active = true, ammo = t.ammo,
      health = t.health, angle = idle, idle = idle, side = facing < 0 and -1 or 1,
      sweep_dir = 1, shots = 0, firing = false, anim = 0, rotating = false,
      servo_sound = 0, fire_sound = 0, beep = 0, activate = 0, cooldown = 0,
      had_target = false, lost = false, seen = {}, recoil = 0,
    }
    state[body.id] = s
    s.gun = rider(t.art.gun, x, worm.y - t.muzzle_up, worm, t.kind .. "_head")
    if t.art.flare then s.flare = rider(t.art.flare, x, worm.y - t.muzzle_up, worm, t.kind .. "_flare") end
    if t.art.barrel then s.barrel = rider(t.art.barrel, x, worm.y - t.muzzle_up, worm, t.kind .. "_barrel") end
    sync(body, s)
    return body, s
  end

  -- Each turn reloads and reactivates every turret, and forgets what moved
  -- and what it aimed at. Order-independent: each entry gets the same reset.
  wa.on.worm_message(function(worm, msg)
    if msg ~= wa.msg.START_TURN then return end
    active_alliance = worm.alliance
    for _, s in pairs(state) do
      s.ammo, s.active, s.had_target, s.tid, s.lost, s.seen = t.ammo, true, false, nil, false, {}
    end
  end, { msgs = { wa.msg.START_TURN } })

  t.state = state -- for the Highlander mock
  return t
end

return turret
