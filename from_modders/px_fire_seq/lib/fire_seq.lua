-- fire_seq.lua -- the sequential-firing base: fire a shot, then the rest of a
-- burst `delay` frames apart, from two helpers.
--
-- Why this exists
-- ---------------
-- Project X sequences a weapon's shots by overriding `CWorm::FireFinal` and
-- *returning before* the stock `super` so that WA itself loops the shot:
--
--   Ripper Star, `ripper_fire.txt:11-32`   -- 15 shots while `RSShotsFired<=14`
--   Megashark,   `megashark_firing.txt:49-76` -- 12 shots while `MShotsFired<=11`
--
-- Both hold `nShoots = 1; nShooted = 0;` every frame (`ripper_fire.txt:42-47`,
-- `megashark_firing.txt:123-128`) so WA keeps firing and the aim stays live.
-- API 4 exposes exactly those two fields -- `worm.shots_to_fire` and
-- `worm.shots_fired`, "Project X's nShoots and nShooted"
-- (`crates/lua-host/src/actor.rs:1386-1405`): while fired is below to-fire WA
-- fires the slot again after its own weapon delay, so a pack that holds them
-- at 0 and 1 each frame keeps the worm in its firing state -- its firing
-- animation, and a `keep_while_firing` hand, run through the whole burst
-- (`laser_gun.lua:180`, the laser).
--
-- So this base does both. It fires the first shot from the caller's `on_fire`
-- and the rest from a hidden timer actor, one every `delay` frames, so the
-- cadence is the pack's and not WA's weapon delay; and the timer's brain
-- holds the two counters every frame, so the worm does not leave its firing
-- state while the burst runs. That is the laser's exact shape: the shot
-- starts the effect, and only the actor's brain touches the counters
-- (`laser_gun.lua:164-201`, never in `on_fire`).
--
-- Those held counters make WA fire the slot again after its own delay, and
-- every one of those shots reaches the caller's `on_fire` again -- which calls
-- a helper here again. The worm is marked mid-burst, so such a re-entry fires
-- nothing, exactly as the laser's `lasers[w.id]` guard swallows WA's re-fire
-- (`laser_gun.lua:155`). When the last shot has left, the counters are ended
-- (`shots_fired = shots_to_fire`, as the laser ends its beam,
-- `laser_gun.lua:147`) and the guard drains for `DRAIN` frames: a re-entry WA
-- had already queued is swallowed there rather than turned into a second
-- burst, and then WA's own retreat runs as it would.
--
-- The counters are written **only from the timer's brain**, never from
-- `on_fire` -- the laser does the same, and for a reason that bites a
-- projectile: `on_fire` runs inside WA's `CreateWeaponProjectile` hook
-- (`crates/engine/src/actor.rs:778-793`), so grounding WA's fire loop from
-- there changes its state from inside its own iteration. The laser holds them
-- a frame later, from the actor (`laser_gun.lua:180`).
--
-- API 4 has no global shot hook (`crates/lua-host/src/api.rs:587-643`; the
-- `on_fire` claims are per weapon), so the first shot still comes from the
-- caller's `on_fire`, and the re-entries reach that same function.
--
-- The same code serves a Lua actor (`fire_sequential_actor`) and a real WA
-- missile (`fire_seq_mis`, `wa.weapons.launch`,
-- `contributing-with-an-agent.md:155`).
--
-- Offset: a projectile that starts inside the firing worm bursts on it at
-- once. WA's own muzzle puts a shot 3.4 px above the worm's centre and the
-- worm's collision circle is 6 px (`wa.world.trace`'s worm radius), so a
-- launch from the muzzle begins *inside* the worm. The laser starts its beam
-- 24 px out for the same reason (`laser_gun.lua:53`); `standoff = n` pushes
-- every shot's spawn point `n` pixels along its own velocity, on top of the
-- caller's own muzzle offset, so the body starts clear of the worm. PX's
-- offsets are kept and this is added; it changes nothing else about the shot.
--
-- Interrupts: the brain holds the counters only while the worm is really
-- firing for this weapon. Every frame it ends the burst early -- and ends WA's
-- repeat fire -- when the worm is dead, is not the turn's worm, no longer
-- holds this weapon (`cancel_weapon`), or is in a state it does not fire in:
-- the laser's own stop line and state list (`laser_gun.lua:39-40`, `:176`).
-- A blast, a teleport or a push that knocks the worm into a tumble or a slide
-- ends the burst instead of firing into it. The timer survives a nearby blast
-- (`persist = true`), so this check -- not the actor's death -- decides, and a
-- burst that is interrupted always ends the counters and the guard here.
--
-- Cancelling: `seq.cancel(owner)` stops the burst running for that worm. It
-- ends WA's shot counters on the spot, so the fire method leaves instead of
-- re-entering with a weapon an impact may have cleared; the timer settles the
-- burst on its next tick (`on_done`), outside WA's fire call. A new burst may
-- start once the timer lets go, which is all a caller needs to chain one.
-- Despawning the returned actor stops the shots but leaves the counters held,
-- so use `cancel` rather than despawning.
--
-- How to call
-- -----------
--   local seq = require("lib/fire_seq")
--
--   -- 12 actor bullets, one per frame
--   seq.fire_sequential_actor({
--     owner = ev.worm, count = 12, delay = 1,
--     cancel_weapon = "px.megashark",       -- end the burst if the worm leaves it
--     sprite = "<your bundle>/sprites/<weapon>/bullet", gravity = false, collide = false,
--     standoff = 12,                        -- spawn 12 px out, clear of the worm
--     x = function(i, w) return w.x + 2 * w.facing end,
--     y = function(i, w) return w.y - 3 end,
--     vx = function(i, w) ... end, vy = function(i, w) ... end,
--     spread = { y = 0.7 },                 -- +-0.7 px/frame, wa.random
--     on = function(a) ... end,             -- the bullet's brain
--   })
--
--   -- 15 real WA missiles
--   seq.fire_seq_mis({
--     weapon = "px.ripper_star", owner = ev.worm, count = 15, delay = 1,
--     cancel_weapon = "px.ripper_star",
--     standoff = 12,
--     x = ..., y = ..., vx = ..., vy = ...,
--     missile = { explosion = { power = 40 } },
--   })
--
-- `x`, `y`, `vx`, `vy` are a number or a `function(i, worm)` called again for
-- every shot, so a live aim (the laser's, `laser_gun.lua:132-151`) stays live.
-- `i` is 1 for the first shot. `count` is the *total*, so `count = 12` is
-- twelve shots, not one plus twelve.
--
-- `spread` is `{ x = n, y = n }`, the maximum absolute jitter in px/frame added
-- to that axis after the shot is resolved; it is drawn with `wa.random` over
-- integer thousandths, so every peer gets the same value (PX's
-- `RandomFloat(-0.7,0.7)` in `megashark_firing.txt:60` is `spread = { y = 0.7 }`).
--
-- `delay` is a number or a `function(i, worm)` called for the shot it spaces.
-- `on_shot(i, worm)` runs before every shot (a per-shot sound, a HUD line);
-- `on_done(owner, fired)` runs when the burst ends: after the last shot, on a
-- cancel, or on an interruption. `fired` is the number of shots that left,
-- including one launched in the same tick as a cancel.
--
-- `standoff = n` moves every shot's spawn point `n` pixels along its own
-- velocity after `x`/`y`/`vx`/`vy` are resolved, so a projectile does not
-- start inside the firing worm (the laser's 24 px, `laser_gun.lua:53`).
--
-- `cancel_weapon = "<id>"` is the id the worm must still hold for the burst to
-- go on; `worm.weapon` is checked against it each frame, as the laser checks
-- its own (`laser_gun.lua:176`). Left out, only the worm's life, turn and
-- state are checked.
--
-- Both helpers return the timer actor; it is `nil` when `count <= 1`, the
-- burst could not start, or a burst for this worm is already in flight.
-- Despawning it early stops the rest of the burst but leaves the worm's
-- counters held, so a caller that cancels must end them itself
-- (`worm.shots_fired = worm.shots_to_fire`).
-- Simulation callbacks only: the first shot and every later one spawn actors or
-- launch missiles, which the engine refuses outside one
-- (`contributing-with-an-agent.md:60`).
--
-- A component's file, and anything it requires, runs where `wa` does not exist
-- yet: this module is pure data at load and touches `wa` only inside the two
-- helpers.

local M = {}

-- Keys that belong to the sequencer, not to the shot. Everything else in the
-- caller's table is handed to `wa.actors.spawn` / `wa.weapons.launch`
-- untouched. (The `spawn`/`launch` parsers ignore unknown keys, but passing
-- `count` on to an actor would be a lie about the actor's own fields, and
-- `standoff`/`cancel_weapon` are the sequencer's business.) `weapon` is
-- deliberately **not** here: `fire_seq_mis` needs it for `wa.weapons.launch`.
local CONTROL = {
  count = true, delay = true, spread = true, on_shot = true, on_done = true,
  standoff = true, cancel_weapon = true,
}

local function is_control(k) return CONTROL[k] == true end

-- Copy the shot spec without the sequencer's keys. Values (functions, tables)
-- are shared, never mutated: `wa.weapons.launch` copies the missile table
-- itself, and a spawn spec is read once.
local function shot_spec(t)
  local out = {}
  for k, v in next, t do
    if not is_control(k) then out[k] = v end
  end
  return out
end

-- A number, or a function of (shot number, worm). `i` is 1-based.
local function value(v, i, w, fallback)
  if type(v) == "function" then return v(i, w) end
  if v == nil then return fallback end
  return v
end

-- `wa.random` takes inclusive integer bounds and errors on a fractional or an
-- empty range (`api.rs`, "random"), so a float spread is scaled to thousandths
-- and rounded first. The same call on every peer gives the same thousandths,
-- and `/1000` is exact enough for a velocity (no table, no clock, no
-- `math.random` -- `contributing-with-an-agent.md:61-63`).
local function jitter(amount)
  if not amount or amount <= 0 then return 0 end
  local n = math.floor(amount * 1000 + 0.5)
  if n < 1 then return 0 end
  return wa.random(-n, n) / 1000
end

-- Resolve one shot's position and velocity: the velocity first (so a standoff
-- can be taken along it), then the position, then the spread.
local function resolve(spec, t, i, w)
  spec.vx = value(t.vx, i, w, 0)
  spec.vy = value(t.vy, i, w, 0)
  local spread = t.spread
  if spread then
    spec.vx = spec.vx + jitter(spread.x)
    spec.vy = spec.vy + jitter(spread.y)
  end
  spec.x = value(t.x, i, w, w and w.x or 0)
  spec.y = value(t.y, i, w, w and w.y or 0)
  -- `standoff`: push the spawn point out along the shot's own direction, so a
  -- projectile does not start inside the firing worm and burst on it at once.
  -- The laser starts its beam 24 px out for the same reason (`laser_gun.lua:53`).
  local so = t.standoff
  if so and so > 0 then
    local d = math.sqrt(spec.vx * spec.vx + spec.vy * spec.vy)
    if d > 0 then
      spec.x = spec.x + (spec.vx / d) * so
      spec.y = spec.y + (spec.vy / d) * so
    end
  end
  return spec
end

-- The worms mid-burst, by id. While a burst runs its counters are held, so
-- WA fires the slot again each delay; every one of those shots reaches the
-- caller's `on_fire`, which calls a helper here again. The entry says one is
-- already in flight, so the re-entry fires nothing -- the laser's guard
-- (`laser_gun.lua:155`).
local running = {}
-- Bursts whose `on_done` has already run, still held only so WA's queued
-- re-fire is swallowed. `M.cancel` reports these as nothing left to settle.
local settled = {}
-- Worms whose burst has been told to stop (`M.cancel`). The timer's brain
-- ends it and settles `on_done` outside WA's fire call, so an impact can
-- cancel the burst without touching the fire loop mid-iteration.
local cancelled = {}

-- Frames the guard stays after the last shot, so a re-entry WA had already
-- queued is swallowed rather than starting a second burst. Ten, as the
-- laser keeps its entry ten frames past the beam's end (`laser_gun.lua:170`).
local DRAIN = 10

-- The states a worm is not firing in, the laser's own list
-- (`laser_gun.lua:39-40`) by WA's raw state. A worm the burst is firing for
-- must not be in one: a blast, a teleport or a push knocks it into a tumble
-- (0x7F), a slide (0x7E, WA's airborne), a hit (0x80) or a blast (0x81), and
-- the burst ends there instead of firing into the interruption.
--
-- Raw values, not `worm.state` labels: `worm_state_name` deliberately names
-- only some states (`crates/lua-host/src/actor.rs:2189-2207`) -- walking
-- (0x66), hit (0x80), blasted (0x81), dying (0x82), drowning (0x85) and dead
-- (0x87) all read `nil` -- so a label list silently missed exactly the
-- states a blast puts a worm in. `state_id` is the raw value (`:1469-1475`);
-- the names are `crates/game/src/worm_state.rs:26-59`. The firing states
-- 0x67-0x6B are absent, so a worm still firing never trips it.
local NOT_FIRING = {
  [0x65] = true, -- standing
  [0x66] = true, -- walking
  [0x6C] = true, -- punching
  [0x6E] = true, -- drilling
  [0x6F] = true, -- teleporting
  [0x70] = true, -- rope_firing?
  [0x71] = true, -- torching?
  [0x73] = true, -- rope_rolling?
  [0x76] = true, -- getting_up
  [0x77] = true, -- jump_prepare
  [0x78] = true, -- jetpacking
  [0x79] = true, -- jumping
  [0x7A] = true, -- jump_falling
  [0x7B] = true, -- roping?
  [0x7C] = true, -- bungee
  [0x7D] = true, -- parachuting
  [0x7E] = true, -- falling / sliding
  [0x7F] = true, -- tumbling
  [0x80] = true, -- hit
  [0x81] = true, -- blasted
  [0x82] = true, -- dying?
  [0x85] = true, -- drowning?
  [0x86] = true, -- frozen
  [0x87] = true, -- dead?
}

-- The common burst runner. `fire(i)` is called once per shot; it must not
-- itself throw for a recoverable miss (the missile path wraps `launch`).
-- `weapon`, when given, is the id the worm must still hold for the burst to go
-- on (the laser's `w.weapon ~= "px.laser_gun"`, `laser_gun.lua:176`).
local function run(owner, count, delay, fire, weapon, on_done)
  if not owner or count < 1 then return nil end

  local id = owner.id
  -- A burst for this worm is already in flight: this call is WA's own re-fire
  -- of the slot, made by the held counters, and the burst owns every shot.
  if id ~= nil and running[id] then return nil end

  local function alive()
    -- `hp` is 0 for a dead worm; the handle itself stays readable for the
    -- turn, as the laser precedent assumes (`laser_gun.lua`).
    return owner.hp and owner.hp > 0
  end

  if not alive() then return nil end

  -- WA ends the repeat fire, as when its shots run out (`laser_gun.lua:147`).
  local function end_fire()
    if owner.shots_to_fire then owner.shots_fired = owner.shots_to_fire end
  end
  -- Hold WA in its firing state: with fired below to-fire WA fires the slot
  -- again after its own delay, so the worm keeps its firing animation (and a
  -- `keep_while_firing` hand) through the burst (`laser_gun.lua:180`).
  local function hold()
    owner.shots_fired, owner.shots_to_fire = 0, 1
  end
  local function release()
    if id ~= nil then
      running[id] = nil
      settled[id] = nil
      cancelled[id] = nil
    end
  end
  -- Shots that have left, including one launched in the same tick as a cancel.
  local left = count - 1
  -- End the burst here: stop WA's repeat fire, settle what it owed (`on_done`),
  -- and let the next burst start. `fired` is for ammo accounting: every path
  -- that ends a burst comes through here, so a caller cannot miss a blast,
  -- death, turn end or weapon swap by watching only its own cancel key.
  local function settle()
    if id ~= nil then settled[id] = true end
    end_fire()
    if on_done then on_done(owner, count - left) end
    release()
  end
  local function frame_delay(i)
    return math.max(1, math.floor(value(delay, i, owner, 1)))
  end
  -- The laser's stop line (`laser_gun.lua:176`): a worm that died, is no
  -- longer the turn's worm, changed weapon, or was knocked out of its firing
  -- state has interrupted the burst. The counters must then be ended at once,
  -- or WA would keep firing a burst nothing is driving.
  local function interrupted()
    return cancelled[id] == true
      or not alive() or not owner.turn
      or weapon == nil
      or (weapon ~= nil and owner.weapon ~= weapon)
      or NOT_FIRING[owner.state_id] == true
  end

  if id ~= nil then running[id] = true end
  fire(1)
  if count == 1 then
    -- One shot is WA's own; nothing was held, and there is nothing to end.
    release()
    return nil
  end
  -- **Not held here.** `on_fire` for a projectile runs inside WA's
  -- `CreateWeaponProjectile` hook (`crates/engine/src/actor.rs:778-793`), so
  -- grounding WA's fire loop from this point changes its state from inside its
  -- own iteration. The laser holds its counters a frame later, from the actor
  -- (`laser_gun.lua:180`); so does the timer below.

  local wait = frame_delay(2)
  local drain = 0
  local ticker
  ticker = wa.actors.spawn({
    -- A timer with no body: the same hidden-actor shape as the laser's shot
    -- actor (`highlander_0rang3_test/weapons/laser_gun.lua`). `persist` keeps
    -- it alive through a nearby blast so the stop check below -- and not the
    -- actor's death -- decides, and so the counters are always ended here;
    -- `collide`/`gravity` off so it never moves or blocks anything.
    sprite = false, x = owner.x, y = owner.y,
    gravity = false, collide = false, persist = true, drown = false,
    owner = owner,
    on = function(a)
      -- The brain does not move the body; it is only a frame clock, and the
      -- only safe place to hold the worm's counters every frame (never
      -- `on_fire`: for a projectile that runs inside WA's own fire loop).
      a.vx, a.vy = 0, 0
      if drain > 0 then
        -- The burst is over and WA's repeat fire already ended; hold the
        -- guard a few frames so a re-entry already on its way is swallowed.
        drain = drain - 1
        if drain <= 0 then
          release()
          a:despawn()
        end
        return
      end
      -- The worm's state, and not the actor's, ends the burst: a blast that
      -- interrupts the firing must not be fired into, and the counters must
      -- not be left held (which is what leaves WA looping on a dead burst).
      if interrupted() then
        settle()
        a:despawn()
        return
      end
      wait = wait - 1
      if wait > 0 then hold() return end
      if left > 0 then
        left = left - 1
        local n = count - left
        fire(n)
        if cancelled[id] then
          -- The shot cancelled the burst (an impact told the caller to):
          -- settle it now that WA's fire call has returned.
          settle()
          a:despawn()
          return
        end
        if left > 0 then
          wait = frame_delay(n + 1)
          hold()
        else
          -- The last shot has left: let WA finish the shot and retreat.
          if id ~= nil then settled[id] = true end
          end_fire()
          if on_done then on_done(owner, count) end
          drain = DRAIN
        end
      end
    end,
  })
  return ticker
end

-- Cancel the burst running for `owner`. No further shots leave, and WA's shot
-- counters are ended now so its fire method exits instead of re-entering with
-- a weapon an impact may have cleared. The timer settles the burst on its next
-- tick (`on_done`), outside WA's fire call, so a caller can pay what it owed
-- there. Returns false when there is no burst, or none left to settle (the
-- drain after the last shot); a new burst may start once the timer lets go.
function M.cancel(owner)
  local id = owner and owner.id
  if id == nil or not running[id] then return false end
  cancelled[id] = true
  if owner.shots_to_fire then owner.shots_fired = owner.shots_to_fire end
  return settled[id] ~= true
end

-- Fire `opts.count` actors, `opts.delay` frames apart. Every other key is the
-- actor's spawn spec (its `on` brain included); `x/y/vx/vy` may be functions.
function M.fire_sequential_actor(opts)
  if type(opts) ~= "table" then return nil end
  local count = opts.count or 1
  local delay = opts.delay or 1
  local owner = opts.owner
  if type(owner) ~= "table" and type(owner) ~= "userdata" then
    -- `owner` is the worm userdata; a plain table would still read hp/x/y but
    -- no engine spawn would accept it. Fail loudly enough to be diagnosed.
    wa.log("fire_sequential_actor: owner must be the firing worm")
  end
  local on_shot = opts.on_shot
  local function fire(i)
    if on_shot then on_shot(i, owner) end
    local spec = resolve(shot_spec(opts), opts, i, owner)
    if spec.owner == nil then spec.owner = owner end
    wa.actors.spawn(spec)
  end
  return run(owner, count, delay, fire, opts.cancel_weapon, opts.on_done)
end

-- Fire `params.count` real WA missiles from `params.weapon`, `params.delay`
-- frames apart. Every other key (`missile`, `clusters`, ...) is passed to
-- `wa.weapons.launch` (`contributing-with-an-agent.md:155`).
function M.fire_seq_mis(params)
  if type(params) ~= "table" or not params.weapon then
    wa.log("fire_seq_mis: params.weapon is required")
    return nil
  end
  local count = params.count or 1
  local delay = params.delay or 1
  local owner = params.owner
  local on_shot = params.on_shot
  local failed = false
  local function fire(i)
    if on_shot then on_shot(i, owner) end
    local spec = resolve(shot_spec(params), params, i, owner)
    if spec.owner == nil then spec.owner = owner end
    local ok, err = pcall(wa.weapons.launch, spec)
    if not ok and not failed then
      -- A launch that raises (WA's object pool full) would otherwise stop the
      -- timer's brain for good; the guide's warning and its `pcall` advice
      -- (`contributing-with-an-agent.md:155`).
      failed = true
      wa.log("fire_seq_mis: launch failed: " .. tostring(err))
    end
  end
  -- `weapon` is also the id WA launches as; it doubles as the check the worm
  -- still holds it. `cancel_weapon` overrides it if ever they differ.
  return run(owner, count, delay, fire, params.cancel_weapon or params.weapon,
    params.on_done)
end

return M
