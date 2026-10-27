-- Fire-while-holding Megashark -- Project X's minigun, but the burst lasts as
-- long as Space is held, or until the inventory runs out.
--
-- This is a copy of `megashark.lua` on its own slot (`px.megashark_hold`), so
-- the fixed twelve-shot Megashark and this version can both be in a profile.
-- The shot, the homing, the trail and the record's blast are unchanged; only
-- the burst length and the stop condition differ.
--
--   * The burst is the inventory's ammo at the moment the trigger is pulled:
--     a finite count fires that many bullets, capped at 20, and infinite ammo
--     fires 20. A finite count is written back from `on_done(owner, fired)`,
--     so a cancel, blast, death, turn end or weapon swap settles the exact
--     number of shots that actually left (see `lib/fire_seq.lua`).
--   * A FRAME_FINISH handler reads `wa.world.keys().space`. The moment Space
--     is not held, it calls `seq.cancel`, so releasing the key ends the burst
--     after the shot already in flight. Holding Space keeps the timer firing.
--
-- PX's source:
--
--   * `megashark_firing.txt` -- twelve shots (`MS_BulletAmount = 11` while
--     `MShotsFired<=11`, :23, :53), one per FireFinal loop; each shot plays
--     `item_11.wav` (`:55-57`), adds `RandomFloat(-0.7, 0.7)` to `SpY`
--     (`:60`), lifts the muzzle 3 px and 1.3 px forward -- 2.9 px and 2 px
--     more at aim below 0.164 (`:61-64`) -- and hides the record's missile
--     sprite (`:63`).
--   * `megashark_home.txt` -- the homing: after 90 px from the firing worm
--     (`:59`), every 2 frames (`:137`) it picks the closest *visible* enemy
--     worm (`:146-199`, sight is a terrain trace, `:201-213`), skipping
--     targets already carrying `bulletsPerTarget` bullets (`:181`, default 4)
--     and steering its velocity toward `direction * 15.5` by 0.53
--     (`:125-135`).
--
-- The bullet is a real WA missile: the base's `fire_seq_mis` fires twelve of
-- the record's own (`weps/megashark_wep.wep`, type 1 / method 3), and WA does
-- the flight, the collision with land and worms, the water, the fuse and the
-- explosion. It was a Lua actor that traced its own steps; a bullet that is
-- moved by script can be moved past a wall by the script (and was), a missile
-- cannot. What stays in Lua is PX's homing (`megashark_home.txt`), written to
-- the missile's velocity from `wa.on.missile_frame`. The explosion is the
-- record's: 0x50 is `missile.explosion.push_pct` (the knockback, 670) and 0x54
-- is `missile.explosion.power` (the damage and the radius together, 9).
--
-- The green trail is an addition, not a port: PX's record carries no trail
-- sprite (0x68 = 0), while Terraria's chlorophyte bullets leave a long streak.
-- It is the workspace's `effects_sdk/libs/trail.lua`, sampled by the module's own
-- missile handler once `trail.add` has registered the bullet; the length, width and colour are the request's, not PX's.
--
-- The hold is PX's Megashark gun: frame 1 (1-based) of
-- `PX_pending/weapgunssheet.png`, with PX's `CWormAnimParams`
-- (`mega_spb.txt:14-29`: `draw_hand = false`, `hand_radius = -6`,
-- `hand_rotation = -0.5`, `hand_radial_rotation = 1.0`,
-- `weap_rotation = 1.0`, `weap_radial_rotation = 1.0`, `weap_radius = 0`,
-- `zplane = 6`, `subSpriteNumber = 1`). The bullet sprite is a stand-in: the
-- record is drawn from `redWeapSheet` subsprite 4 (`mega_spb.txt:55-63`) or
-- `clorophyte.png` (`:45`, not in the repo), and neither sheet is available,
-- so `sprites/megashark/bullet/frame000.png` is a small green orb tinted to
-- chlorophyte -- replace it with the real sheet when it turns up.
--
-- Three mechanical departures from PX's numbers:
--
--   * the record's hold pose (+0x34) is 0 in PX's own `MEGASHARK.wep`, and WA
--     answers a fire-state sprite request with sheet 0 for it. The engine maps
--     that 0 to `weaponlnk*` only in the aiming states (`worm_sprite.rs:374-376`),
--     so in 0x6A/0x6B the worm had no sheet at all and vanished for the length
--     of each shot -- the "missing sprite builder" the burst showed. PX draws
--     the worm himself and never looks at WA's pose. The port names the
--     minigun pose (4, the Ripper's value, `Ripper + Ripper Star.wep` +0x34):
--     a fire state then asks for `wminif` 573-575, which the claim maps to
--     `weaponfire*` (`worm_sprite.rs:283-290, 387-389`) and
--     `expand_aim_claims` fills from the `weaponlnk` sheet (`:521-529`). A byte edit
--     to the `.wep` would do the same; the Lua record table names it.
--   * `standoff = 12`. PX's muzzle sits ~3 px above the worm's centre, and the
--     worm's collision circle is 6 px, so a bullet spawned there traces into
--     the land (or the worm) on its first frame and explodes on the owner with
--     the record's 670 push. Every bullet is pushed 12 px along its own
--     launch direction, as the laser draws its beam from 24 px out
--     (`laser_gun.lua:53`).
--   * the burst ends early if the worm is knocked out of its firing state (a
--     blast, a push, a teleport), so a burst that is interrupted does not keep
--     firing into the interruption; `cancel_weapon` and the state list live in
--     `lib/fire_seq.lua`.

local seq = require("lib/fire_seq")
local sb = require("lib/px_sprite_builder")
local trail = require("wf-lib/effects/trail")
local hold_art = require("lib/px_hold_art")

local M = {}

local function placed(ctx)
  local informed = false
  if type(ctx.weapons) == "table" then
    informed = true
    if ctx.weapons[ctx.id] ~= nil then return true end
  end
  if type(ctx.placed) == "table" then
    informed = true
    for _, weapon in ipairs(ctx.placed) do
      if weapon == ctx.id or (type(weapon) == "table" and weapon.id == ctx.id) then return true end
    end
  end
  return not informed
end

function M.install(ctx)
  if not placed(ctx) then
    wa.log("Megashark (hold): in no panel slot; nothing registered")
    return
  end

  local ID = ctx.id
  local ART = "sprites/megashark/"
  local SND = "sounds/megashark/"

  -- The module's engine callbacks (`wa.on.missile_frame`, `wa.on.draw`) and
  -- its driver. A component's file, and anything it requires, runs where `wa`
  -- does not exist yet, so this is registered here, not at load.
  trail.install()

  -- PX's numbers.
  -- The inventory this weapon uses. `worm:ammo` is team ammo for the weapon's
  -- slot, exactly as Highlander writes it; `-1` is WA's infinite. The fixed
  -- Megashark fires twelve; this one fires the inventory's count up to 20.
  local MAX_BURST = 20
  -- Frames between the shots of the burst. PX does not impose one: it returns
  -- before WA's `super` and lets WA's own fire loop call `FireFinal` again,
  -- which it does every 4 frames for this record (`on_fire` in wkLua.log:
  -- frames 879, 883, 887, 891; the same 4 in `ripper_star.lua`). The timer in
  -- `lib/fire_seq.lua` replaces WA's loop, so it must use WA's interval or the
  -- burst runs four times too fast.
  local SHOT_DELAY = 4
  local SPEED = 15.5      -- missileSpeed (megashark_home.txt:125)
  local TURN = 0.53       -- homingStrength (:126)
  local ARM_DIST = 90     -- activation distance (:59)
  local COOLDOWN = 2      -- homingCooldown (:137)
  local SENSOR2 = 199900  -- sensorRadiusSqr (:150)
  local PER_TARGET = 4    -- bulletsPerTarget default (:136, nerfBC)
  local LOW_AIM = 0.164   -- low-angle extra offset (megashark_firing.txt:64)

  -- The bullet's trail. PX's record carries no trail sprite (0x68 = 0), and the
  -- clorophyte round's long green streak is the request, not a record value
  -- (Terraria's chlorophyte bullet leaves a trail about 25 tiles long). At
  -- 15.5 px a frame, 26 points is ~400 px; `every = 1` keeps it smooth. The
  -- module's defaults are PX's bullet's 12 points / every 2 frames / 8 and 13
  -- wide (`effects_sdk/libs/trail.lua:33-34`), so both the length and the width are the
  -- request's.
  local TRAIL = { max = 26, every = 1, core_w = 5.0, glow_w = 10.0,
    r = 90, g = 255, b = 120 }

  local function current_worm()
    for _, w in ipairs(wa.worms.all()) do
      if w.turn then return w end
    end
  end

  -- Per-bullet homing state, keyed by missile id (integers, so every peer's
  -- table has the same keys; `pairs` is never used to order anything).
  local state = {}
  -- PX's `bulletsOnMe`: how many bullets have committed to each worm, so a
  -- twelfth bullet looks for someone else instead of stacking on one target.
  local on_target = {}

  -- Worms whose hold-burst this weapon started and whose Space key still owns
  -- it. The timer's `on_done` clears the entry on every end, so a later frame
  -- cannot cancel a different burst for a worm that has moved on.
  local holding = {}
  wa.on.worm_message(function(worm)
    if not holding[worm.id] then return end
    -- The base's own `cancel_weapon` check ends a burst when the selection
    -- changes or the worm is no longer active; clear our flag with it, so a
    -- stale entry cannot cancel the next burst.
    if not worm.turn or worm.weapon ~= ID then
      holding[worm.id] = nil
      seq.cancel(worm)
      return
    end
    if not wa.world.keys().space then
      holding[worm.id] = nil
      seq.cancel(worm)
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })

  local function release(s)
    if s.targetId then
      local n = (on_target[s.targetId] or 1) - 1
      if n > 0 then on_target[s.targetId] = n else on_target[s.targetId] = nil end
      s.targetId = nil
    end
  end

  local function worm_by_id(id)
    for _, w in ipairs(wa.worms.all()) do
      if w.id == id then return w end
    end
  end

  -- PX's IsTargetVisible (:201-213): a terrain trace with no hit.
  local function visible(m, w)
    local hit = wa.land.trace(m.x, m.y, w.x, w.y)
    return not (hit and hit.hit)
  end

  local function acquire(m, s, owner)
    release(s)
    local best, bestD2
    for _, w in ipairs(wa.worms.all()) do
      -- PX skips the owner, its own team and its own colour, dead worms, and
      -- any already carrying the per-target cap (:169-181).
      if w.id ~= owner.id and w.team ~= owner.team and w.hp > 0
        and (on_target[w.id] or 0) < PER_TARGET then
        local dx, dy = w.x - m.x, w.y - m.y
        local d2 = dx * dx + dy * dy
        if d2 < SENSOR2 and (not bestD2 or d2 < bestD2) and visible(m, w) then
          best, bestD2 = w, d2
        end
      end
    end
    if best then
      s.targetId = best.id
      on_target[best.id] = (on_target[best.id] or 0) + 1
    end
    return best
  end

  -- PX's steering (:125-135): move the current velocity a fraction of the way
  -- to `direction * SPEED`.
  local function steer(m, tx, ty)
    local dx, dy = tx - m.x, ty - m.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 0 then dx, dy = dx / d, dy / d end
    m.vx = m.vx + (dx * SPEED - m.vx) * TURN
    m.vy = m.vy + (dy * SPEED - m.vy) * TURN
  end

  -- The homing, once per game frame. The shooter is the turn's worm: WA hands
  -- the handler no owner, and a burst never outlives its turn.
  wa.on.missile_frame(function(m)
    if m.weapon ~= ID then return end
    local s = state[m.id]
    if not s then
      s = { armed = false, cd = 0, targetId = nil, owner = current_worm() }
      state[m.id] = s
      -- WA launches these itself, so the trail is registered here, on the
      -- bullet's first frame (as `ripper_star.lua` does for its stars).
      if not trail.has(m.id) then trail.add(m.id, s.owner, TRAIL) end
    end
    if m.phase == "pre" then return end
    local owner = s.owner
    if not owner then return end

    if not s.armed then
      local dx, dy = m.x - owner.x, m.y - owner.y
      if dx * dx + dy * dy > ARM_DIST * ARM_DIST then
        s.armed = true     -- PX arms and returns; guidance starts next frame
        s.cd = 0
      end
      return
    end

    s.cd = s.cd - 1
    if s.cd > 0 then return end
    s.cd = COOLDOWN
    local target = s.targetId and worm_by_id(s.targetId)
    if target then
      local dx, dy = target.x - m.x, target.y - m.y
      -- PX drops a target past the sensor or with no health left (:72-81).
      if target.hp <= 0 or dx * dx + dy * dy > SENSOR2 or not visible(m, target) then
        release(s)
        target = nil
      end
    end
    if not target then target = acquire(m, s, owner) end
    if target then
      steer(m, target.x, target.y)
    else
      s.cd = 7 -- PX's "no target" cooldown (:97)
    end
  end)

  -- The bullet in flight: PX hides WA's missile (`ldata->anim.spriteIndex = 0`)
  -- and a follower actor draws the sprite, as the Ripper Star's does.
  sb.flight(ctx, {
    weapon = ID,
    sheet = ART .. "bullet",
    anim = "none",
    frame_fn = function() return 0 end,
    z = wa.depth.OBJECTS - 1,
    mirror = false,
  })

  -- PX's hold, the Megashark gun with its arms baked into the 90x90 cell.
  --
  -- The engine's `spec.hold` draws the aiming frames: its `grow()`
  -- (`worm_hold.rs:121-135, :351-355`) is PX's `scale_pick` pick animation
  -- (`worms_anims_script.txt:231-258`), so the gun grows in over the first 20
  -- aiming frames exactly as the builder's. The engine's firing branch needs
  -- `h.firing`, which only the turn's fire message sets (`worm_hold.rs:139-145,
  -- :251-266`), so on WA's own held burst it drops the sheet from the second
  -- shot's firing frames (0x6A/0x6B). `lib/px_hold_art.lua` covers just those
  -- two states, at full size, which is PX's firing branch (`:280-283`).
  --
  -- PX's cell is the 90x90 it was authored, with the arms baked in
  -- (`draw_hand = false`, `mega_spb.txt:22`), so no hand sheet.
  -- `weap_rotation = 1.0` is PX's (`:20`); it makes the angle
  -- `PI - PI * aim` (`worm_hold.rs:346, :365`), the barrel-up convention these
  -- cells are drawn in.
  local hold = {
    weapon = ID,
    sheet = ART .. "hold",
    size = 90,
    keep_while_firing = false,
    -- Swing the gun down and shrink it over the worm's put-away.
    put_away = true,
    weap_rotation = 1.0,
    weap_radial_rotation = 1.0,
    weap_radius = 0.0,
  }

  local spec = {
    wep = "weps/megashark_wep.wep",
    panel_icon = ART .. "icon.png",
    sprites = { ART .. "bullet", ART .. "hold", trail.BEAM, trail.GLOW },
    params = { gpu_prefix = "sprites/" },
    worm_sprites = sb.PX_POSTURE,
    hold = hold,
    sounds = { SND .. "shot.wav" },

    on_fire = function(ev)
      local w = ev.worm
      -- The inventory's count for this slot, before the burst starts. Infinite
      -- is WA's -1; cap it at 20 so one trigger pull cannot lock the match in
      -- a very long burst. A finite write is reconciled from `on_done`; an
      -- infinite stock is left alone.
      local ammo = w:ammo(ID)
      if ammo == 0 then return end
      local shots = ammo < 0 and MAX_BURST or math.min(ammo, MAX_BURST)
      if shots < 1 then return end
      -- WA's muzzle is `CTX_SPAWN_X/Y`, the engine's own computed shot point
      -- (`crates/engine/src/actor.rs:870-889`). Keep its distance from the
      -- worm, but apply it with the worm's *current* facing on every shot: a
      -- script can turn the worm during the burst, and PX re-applies
      -- `1.3 * TurnSide` (and the low-angle `2 * TurnSide`) in every loop
      -- (`megashark_firing.txt:61-64`), so a captured signed x would leave the
      -- rest of the burst firing from the old side.
      local ox = math.abs(ev.x - w.x)
      local oy = ev.y - w.y
      -- PX launches at the record's speed, then steers to 15.5; keep WA's
      -- launch speed when it is usable.
      local speed = math.sqrt(ev.vx * ev.vx + ev.vy * ev.vy)
      if speed < 1 then speed = SPEED end

      -- Live aim, as PX's rebuilt Desc is: 0 straight down, 1 straight up.
      local function dir(ww)
        local ang = (1 - ww.aim) * math.pi
        if ww.facing < 0 then ang = 2 * math.pi - ang end
        return wa.math.sin(ang), -wa.math.cos(ang)
      end

      local timer = seq.fire_seq_mis({
        weapon = ID,
        -- End the burst if the worm is knocked out of its firing state (a
        -- blast, a push, a teleport); see `lib/fire_seq.lua`.
        cancel_weapon = ID,
        -- The muzzle sits ~3 px above the worm's centre, inside its ~6 px
        -- collision circle, so a bullet launched there bursts on the owner at
        -- once. Push every bullet 12 px along its own launch direction, as the
        -- laser draws its beam from 24 px out (`laser_gun.lua:53`).
        standoff = 12,
        owner = w,
        count = shots,
        delay = SHOT_DELAY,
        x = function(i, ww)
          -- PX's forward offset, including the low-angle extra (2 px) that
          -- `megashark_firing.txt:64` adds with the 2.9 px lift.
          local low = ww.aim < LOW_AIM and 2.0 or 0
          return ww.x + ww.facing * (ox + 1.3 + low)
        end,
        y = function(i, ww)
          return ww.y + oy - 3.0 - (ww.aim < LOW_AIM and 2.9 or 0)
        end,
        vx = function(i, ww)
          local dx = dir(ww)
          return dx * speed
        end,
        vy = function(i, ww)
          local _, dy = dir(ww)
          return dy * speed
        end,
        spread = { y = 0.7 }, -- RandomFloat(-0.7, 0.7) (:60)
        on_shot = function(i, ww)
          wa.sound.play(ww, SND .. "shot.wav")
        end,
        -- Every way a burst ends -- last shot, Space released, blast, death,
        -- turn end or weapon swap -- reaches here with the number of shots
        -- that actually left. Absolute write, as Highlander does: adding to
        -- an infinite stock would leave it infinite, and WA may already have
        -- spent the first unit.
        on_done = function(ww, fired)
          holding[ww.id] = nil
          if ammo >= 0 then
            ww:ammo(ID, { set = math.max(0, ammo - (fired or 0)) })
          end
        end,
      })
      if timer then holding[w.id] = true end
    end,

    -- The bullet is gone (hit, water, fuse): give back the target it held and
    -- drop its trail. The blast itself is the record's.
    on_explode = function(ev)
      local id = ev.missile
      if not id then return end
      local st = state[id]
      if st then release(st); state[id] = nil end
      trail.drop(id)
    end,
  }
  spec.handling = { ends_turn = true }
  -- `fires.subtype` is the hold pose, +0x34 (`web/weapon-editor/wep_schema.js:36-50`,
  -- `weapons/record.rs:202`). PX's record has 0, which is no pose; 4 is the
  -- minigun's, the Ripper's working value. See "Three mechanical departures".
  spec.fires = { subtype = 4 }
  -- The same spec also drives the firing-only fallback; see the block above.
  hold_art.add(hold)
  wa.weapons.replace(spec)
end

return M
