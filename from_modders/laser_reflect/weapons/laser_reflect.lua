-- Reflective Laser Gun -- Project X's weapon_gun_laserreflect (PX's reflaser).
--
-- PX's CReflLaser is a buffered shot, not a beam that burns like the Laser Gun's
-- CLaserRay: at FireFinal it computes the whole reflected path once -- three
-- straight runs with at most two bounces by default, the `bounces` option --
-- (reflaser.txt:116-186), then freezes the worm for 30 frames while a thin beam
-- shows the path. On the impact frame it does one collect pass over every run
-- and sends all the damage at once (reflaser.txt:192-271), then lingers 12
-- frames with a bright beam that fades (reflaser.txt:445-469).
--
-- The record is PX's own weapon_lasergun.wep (a gun: its fire reaches on_fire,
-- which is what lets this run instead of a bullet); the art and sounds are the
-- Laser Gun's, as PX ships them in this pack. PX's mask is an 11x11 square
-- around the beam; `wa.world.trace` with radius 5 is the same reach.
--
-- PX keeps the worm in the firing state with `nShoots = 1; nShooted = 0` each
-- frame (reflaser.txt:438-439) and ends the shot with `SetState` (Free,
-- reflaser.txt:324-334). Here the held counters make WA fire the slot every
-- frame -- the record's gun header has `shot_interval_ms` 0 -- and each of
-- those re-fires reaches on_fire again. So the guard outlives the beam by
-- `DRAIN_FRAMES`: the counters are ended first, and only then is WA allowed to
-- see a free slot, or its queued re-fire starts a second beam.
local M = {}

local CHARGE_FRAMES = 30    -- PX's CastFrames: 0.5 s at 50 fps
local LINGER_FRAMES = 12    -- PX's LingerTimer
local REACH = 2048          -- PX traces 2048 px for a wall
local BOUNCES = 2           -- PX allows three runs; the `bounces` option moves this
local MAX_BOUNCES = 10      -- the option's ceiling
local DRAIN_FRAMES = 10     -- frames the guard swallows WA's queued re-fire for
local DRAIN_CAP = 60        -- ...and the most it will wait for WA to leave firing
local FIRING = { [0x6A] = true, [0x6B] = true } -- WA's two firing states
local MASK_RADIUS = 5       -- PX's 11x11 laser mask
local NORMAL_LIFT = 4       -- PX starts the next run 4 px off the wall
local PUSH = 5              -- PX's fparams = direction * 5
local WORM_DAMAGE = 40      -- PX's params[5] by class
local OIL_DAMAGE = 55
local OTHER_DAMAGE = 18
local LOOP_EVERY = 15       -- PX plays the charge loop every 7th frame
local CHARGE_MIN_W = 2.4    -- thinnest the charging beam gets
local IMPACT_MAX_W = 5.5    -- thickest the hit/linger beam gets
local MAX_HITS = 32         -- PX's RL_HitObjs
local TARGETS = { "worms", "mines", "crates", "oil" }

function M.install(ctx)
  -- `laser` reads wa.depth at load, so it is required here, not at declaration.
  local laser = require("lib/laser")
  local ART = "sprites/laser_gun/"
  local SND = "sounds/laser_gun/"

  local bounces = BOUNCES
  if ctx.option then bounces = ctx.option("bounces") or bounces end
  if bounces < 0 then bounces = 0 elseif bounces > MAX_BOUNCES then bounces = MAX_BOUNCES end

  -- One live shot per worm, as PX keeps its CReflLaser on the worm.
  local shots = {}

  -- The reflected path: a run from (x, y) along (dx, dy) to the first land, its
  -- normal, and the next run from just off that wall. PX's RL_ComputePath.
  local function path(x, y, dx, dy)
    local segs = {}
    for i = 1, bounces + 1 do
      local ex, ey = x + REACH * dx, y + REACH * dy
      local land = wa.world.trace{ x0 = x, y0 = y, x1 = ex, y1 = ey, radius = 0, with = { "terrain" } }
      local hx, hy = ex, ey
      if land and land.hit then
        hx, hy = land.x, land.y
      elseif land and land.starts_solid then
        -- The muzzle is inside the land: no run at all, as PX's TraceLine gives.
        hx, hy = x, y
      end
      segs[#segs + 1] = { x1 = x, y1 = y, x2 = hx, y2 = hy, dx = dx, dy = dy }
      if i > bounces or not (land and land.hit) then break end
      -- RL_ReflectDir: flip a normal that faces along the incoming dir, then
      -- mirror the direction in it.
      local nx, ny = land.nx or 0, land.ny or -1
      local dot = dx * nx + dy * ny
      if dot > 0 then nx, ny, dot = -nx, -ny, -dot end
      local rx, ry = dx - 2 * dot * nx, dy - 2 * dot * ny
      local len = math.sqrt(rx * rx + ry * ry)
      if len < 0.001 then len = 1 end
      dx, dy = rx / len, ry / len
      x, y = hx + nx * NORMAL_LIFT, hy + ny * NORMAL_LIFT
    end
    return segs
  end

  -- PX's RL_CollectHits: walk each run with the laser mask, adding every object
  -- found to the ignore list so the next trace sees past it. The shooter is
  -- ignored from the start (reflaser.txt:299-302).
  local function collect(r)
    local ignore = { r.worm }
    local hits = {}
    for _, s in ipairs(r.segments) do
      local x, y = s.x1, s.y1
      local steps = 0
      while #hits < MAX_HITS and steps < MAX_HITS do
        local hit = wa.world.trace{ x0 = x, y0 = y, x1 = s.x2, y1 = s.y2,
          radius = MASK_RADIUS, with = TARGETS, ignore = ignore }
        if not (hit and hit.hit and hit.obj) then break end
        local obj = hit.obj
        ignore[#ignore + 1] = obj
        -- A worm already dead stays out of the messages; every other object in
        -- the beam is hit. Both leave the ignore list, so the pass moves on.
        if obj.kind ~= "worm" or obj.hp > 0 then
          hits[#hits + 1] = { obj = obj, dx = s.dx, dy = s.dy }
        end
        -- Past the contact point, so the run resumes after the object.
        x, y = hit.x + s.dx, hit.y + s.dy
        steps = steps + 1
      end
      if #hits >= MAX_HITS then break end
    end
    return hits
  end

  -- PX's RL_ApplyDamage: one message per object, 40 to a worm, 55 to an oil
  -- drum, 18 to a crate or mine, each with 5 px/frame along its own run.
  local function apply(hits)
    for _, h in ipairs(hits) do
      local obj, vx, vy = h.obj, h.dx * PUSH, h.dy * PUSH
      if obj.kind == "worm" then
        obj:hurt{ amount = WORM_DAMAGE, vx = vx, vy = vy }
      elseif obj.kind == "oil" then
        obj:hit(OIL_DAMAGE, vx, vy)
      elseif obj.kind == "crate" then
        obj:hit(OTHER_DAMAGE, vx, vy)
      elseif obj.kind == "mine" then
        -- PX sends gun damage; a mine is armed instead, as the Laser Gun port
        -- does (object:hit leaves a mine alone).
        obj:arm(obj.fuse < 0 and wa.random(1000, 5000) or obj.fuse)
      end
    end
  end

  -- End WA's repeat fire, as when its shots run out (laser_gun.lua:147): while
  -- the beam ran, the brain held 0 of 1 so the worm stayed in its firing state.
  local function stop_fire(w)
    if w and w.hp > 0 and w.shots_to_fire ~= nil
        and w.shots_fired ~= w.shots_to_fire then
      w.shots_fired = w.shots_to_fire
    end
  end

  local function release(r, a)
    stop_fire(r.worm)
    shots[r.id] = nil
    if a then a:despawn() end
  end

  -- A death or the turn ending drops the shot. The flag is read on the timer's
  -- next tick so the counters are ended from a simulation callback.
  wa.on.turn_end(function(ev)
    local r = ev.worm and shots[ev.worm.id]
    if r then r.cancelled = true end
  end)

  wa.on.death(function(ev)
    local r = ev.victim and shots[ev.victim.id]
    if r then r.cancelled = true end
  end)

  wa.on.draw(function()
    for _, r in pairs(shots) do
      -- The beam is over in the drain; the guard is only soaking re-fires.
      if r.phase ~= 3 then
        local p = 1 - r.charge / CHARGE_FRAMES
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        local color, width
        if r.phase == 0 then
          color = laser.argb(255, { 255, 50 * p, 0 })
          width = CHARGE_MIN_W + (IMPACT_MAX_W - CHARGE_MIN_W) * p
        else
          color = laser.argb(255, { 255, 230, 200 })
          width = IMPACT_MAX_W * (r.linger / LINGER_FRAMES)
          if width < 1 then width = 1 end
        end
        for i, s in ipairs(r.segments) do
          local start_size = i == 1 and 0.5 + 0.5 * p or 0.8
          laser.glow(s.x1, s.y1, 32 * start_size, color)
          laser.beam(s.x1, s.y1, s.x2, s.y2, width, color, width * 0.6)
          laser.glow(s.x2, s.y2, 32 * 0.7, color)
        end
      end
    end
  end)

  local function fire(ev)
    local w = ev.worm
    if not w or shots[w.id] then return end
    local ang = (1 - w.aim) * math.pi
    if w.facing < 0 then ang = 2 * math.pi - ang end
    local dx, dy = wa.math.sin(ang), -wa.math.cos(ang)
    -- PX starts 24 px along the aim from the worm, 2 px over the barrel.
    local x = w.x + 2 * w.facing * dy + 23 * dx
    local y = w.y - 2 + 23 * dy
    local r = { worm = w, id = w.id, phase = 0, charge = CHARGE_FRAMES,
      linger = LINGER_FRAMES, drain = 0, frames = 0,
      segments = path(x, y, dx, dy) }
    shots[w.id] = r
    wa.sound.play(w, SND .. "laser_start.wav")
    wa.actors.spawn({
      sprite = false, x = x, y = y, gravity = false, collide = false, owner = w,
      persist = true, drown = false,
      on = function(a)
        local worm = r.worm
        r.frames = r.frames + 1
        if shots[r.id] ~= r or not worm then
          if a then a:despawn() end
          return
        end
        if r.phase == 3 then
          -- The beam is over and WA's counters are ended. Keep the guard while
          -- WA leaves its fire method: the record fires every frame, so the
          -- shot WA already queued would otherwise start a second beam. A
          -- minimum of DRAIN_FRAMES, then however long WA stays in a firing
          -- state (capped, so a stuck state still ends).
          r.drain = r.drain + 1
          local firing = FIRING[worm.state_id] == true
          if r.cancelled or r.drain >= DRAIN_CAP
              or (r.drain >= DRAIN_FRAMES and not firing) then
            release(r, a)
          end
          return
        end
        -- `frames` is a backstop: the shot always ends even if a counter or a
        -- state test stops making sense.
        if r.cancelled or worm.hp <= 0 or not worm.turn
            or r.frames > CHARGE_FRAMES + LINGER_FRAMES + DRAIN_FRAMES + 30 then
          release(r, a)
          return
        end
        -- PX holds nShoots = 1, nShooted = 0 and the worm's speed at 0 while
        -- the shot is buffered; WA then keeps the firing animation.
        worm.shots_fired, worm.shots_to_fire = 0, 1
        worm.vx, worm.vy = 0, 0
        if r.phase == 0 then
          if r.charge % LOOP_EVERY == 0 then wa.sound.play(a, SND .. "laser_loop.wav") end
          r.charge = r.charge - 1
          if r.charge <= 0 then r.phase = 1 end
        elseif r.phase == 1 then
          -- The hit frame: one collect pass, then every message at once.
          apply(collect(r))
          wa.sound.play(a, SND .. "laser_end.wav")
          r.phase = 2
        else
          r.linger = r.linger - 1
          if r.linger <= 0 then
            -- PX's Free ends the shot and puts the worm out of its firing
            -- state. End the counters; the guard drains a few frames more.
            stop_fire(worm)
            r.phase = 3
            r.drain = 0
          end
        end
      end,
    })
  end

  wa.weapons.replace({
    wep = "weps/laser_reflect.wep",
    -- PX's record is a gun header: three uses per sequence, two bullets each,
    -- an interval of 0 (a shot every frame) and no turn end. PX's own FireFinal
    -- swallows the repeats; here one click must be one beam, so the record is
    -- cut to a single shot and the shot ends the turn. The counters are still
    -- held for the animation, so WA calls the slot every frame: that is what
    -- the guard's drain above absorbs.
    handling = { shots = 1, ends_turn = true },
    gun = { bullets = 1 },
    panel_icon = ART .. "ico_lasergun.png",
    sprites = { ART .. "laser_beam.png", ART .. "laser_glow.png" },
    worm_sprites = {
      weaponlnk = ART .. "aim.png", weaponlnku = ART .. "aimu.png",
      weaponlnkd = ART .. "aimd.png",
      wthrow = ART .. "draw.png", wthrowu = ART .. "drawu.png",
      wthrowd = ART .. "drawd.png",
    },
    sounds = { SND .. "laser_start.wav", SND .. "laser_loop.wav", SND .. "laser_end.wav" },
    params = { gpu_prefix = "sprites/laser_gun/" },
    on_fire = fire,
  })
end

return M
