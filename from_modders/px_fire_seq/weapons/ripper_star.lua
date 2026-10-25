-- Ripper Star -- Project X's Ripper, firing our ninja stars in a flurry.
--
-- PX has two halves:
--
--   * `ripper_fire.txt` -- fifteen shots, one per FireFinal loop, while
--     `RSShotsFired<=14` (:15). Every shot is launched from the worm's live
--     position, 3.4 px up (low angles 3.1 px more, 2 px forward, :17-18), at a
--     speed and angle from `FireAngle`, which `FireFinal` rebuilds for every
--     loop (:19-21, :23): `SpX = TurnSide * (0.5 - |0.5 - FireAngle|) * 45`,
--     `SpY = 45 * (0.5 - FireAngle)` (:20-21). PX starts that angle from
--     `rgFA` (:61-66) and lets the up/down keys move it by 0.010 through the
--     burst (:86-99); WA applies those adjustments to `worm.aim`, so reading
--     the worm's aim on every shot is PX's live `FireAngle` (:96-99). Odd
--     shots nudge the angle -0.010, quarter shots +0.010 (:96-98), the wobble.
--   * `ripper_script.txt` -- the impact, `CMissile::ExplodeAt` (:49-88): the
--     first worm, mine, oil drum or crate within a strict 20 px square gets
--     **4** damage and a quarter of the star's speed (:90-108); failing that,
--     the worm whose turn it is within 25 px; failing both, the star is
--     stamped into the land in one of 32 orientations (:110-151) with
--     `rippers_impact.wav` (:84).
--
-- The star's art is the ninja star's (the request: "Ripper Star launches the
-- shurikens we just did"), so `sprites/ripper_star/stamp` is a copy of
-- `px_hold`'s 32-orientation sheet. PX's own `rippers.png` is a needle, not a
-- star; it is not used. The record's own particle trail is cleared too (0x68,
-- `missile.trail.sprite`, was 457), exactly as the ninja star's record now is,
-- and each star flies on the same grey ribbon as the ninja star
-- (`effects_sdk/libs/trail.lua` with the ninja star's numbers), so the flurry looks like
-- the star the worm threw. The hold is PX's Ripper gun itself: frame 7 (1-based)
-- of `PX_pending/weapgunssheet.png`, drawn with PX's `CWormAnimParams`
-- (`ripper_script.txt:160-179`: `draw_hand = false`, `hand_radius = -6`,
-- `hand_rotation = -0.5`, `hand_radial_rotation = 1.0`,
-- `weap_rotation = 1.0`, `weap_radial_rotation = 1.0`, `weap_radius = 0`,
-- `zplane = 4`, `subSpriteNumber = 7`).
--
-- The sequencing itself is the base's: `lib/fire_seq.lua`, `fire_seq_mis`
-- (fifteen real WA missiles, one every four frames). The record is PX's own
-- (`weps/ripper_star_wep.wep`, type 1 / method 3); its blast is 0, so the 4
-- damage is the port's, exactly as PX's `super` contributes nothing.
--
-- Two departures from PX's numbers, both mechanical:
--
--   * `standoff = 12`. PX's muzzle sits 3.4 px above the worm's centre, and
--     the worm's collision circle is 6 px, so a star launched from there
--     begins inside the firing worm and bursts on it at once. Every star is
--     pushed 12 px along its own launch direction, as the laser draws its beam
--     from 24 px out (`laser_gun.lua:53`). PX's own offsets are unchanged; the
--     standoff is added on top.
--   * the impact goes through WA's hit (`worm:hurt{ vx, vy }`) instead of
--     writing the worm's `vx`/`vy` memory as PX did (`target->SpX = SpX/4`).
--     WA's force fields are where PX's own `M_GUNEXP` put its push, and only
--     that path commits the health when the worm lands
--     (`contributing-with-an-agent.md:66`).
--
-- The burst also ends early if the worm is knocked out of its firing state (a
-- blast, a push, a teleport), so a burst that is interrupted does not keep
-- firing into the interruption; `cancel_weapon` and the state list live in
-- `lib/fire_seq.lua`.

local seq = require("lib/fire_seq")
local sb = require("lib/px_sprite_builder")
local trail = require("wf-lib/effects/trail")
local hold_art = require("lib/px_hold_art")

local M = {}

-- A component in no panel slot registers nothing (REPORT.md 11.13).
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

-- PX's trunc (integer division on fixed point, toward zero).
local function trunc(n) return n < 0 and math.ceil(n) or math.floor(n) end

-- PX's 32 orientations by ratio bins (`ripper_script.txt:116-144`, the same
-- arithmetic the ninja star uses).
local function orientation(vx, vy)
  if vx == 0 then return vy > 0 and 16 or 0 end
  if vy == 0 then return vx > 0 and 8 or 24 end
  if vx > 0 and vy < 0 then return math.min(trunc(3 * vx / -vy), 7) end
  if vx > 0 then return math.min(trunc(8 + 3 * vy / vx), 15) end
  if vy > 0 then return math.min(trunc(16 + 3 * -vx / vy), 23) end
  return math.min(trunc(24 + 3 * -vy / -vx), 31)
end

-- PX's strict square (x > PosX-20 && x < PosX+20, :64); the query is a circle,
-- so ask for a little more and apply the square here.
local function within(o, x, y, r)
  return o and math.abs(x - o.x) < r and math.abs(y - o.y) < r
end

function M.install(ctx)
  if not placed(ctx) then
    wa.log("Ripper Star: in no panel slot; nothing registered")
    return
  end

  local ART = "sprites/ripper_star/"
  local SND = "sounds/ripper_star/"
  local DAMAGE = 4      -- ripper_script.txt:94
  local HIT_R = 20      -- the strict 20 px square (:64)
  local SELF_R = 25     -- and the 25 px square for the turn's worm (:75)
  local SHOTS = 15      -- RSShotsFired<=14 (:15)
  -- Frames between the stars. PX lets WA's own fire loop call `FireFinal`
  -- again; it does so every 4 frames for this record, the same interval as
  -- the Megashark's (`on_fire` in wkLua.log), so the timer must match it.
  local SHOT_DELAY = 4
  local SPEED = 45      -- the constant in PX's velocity (:20-21)
  local LOW_AIM = 0.165 -- the low-angle extra offset (:18)
  local BURIED = { soften = 3, blend = "mix" } -- as the ninja star's

  -- The module's own engine callbacks (`wa.on.missile_frame`, `wa.on.draw`),
  -- registered here because a component's file -- and anything it requires --
  -- runs where `wa` does not exist yet (`px_hold/lib/TRAIL.md`).
  trail.install()

  -- The ninja star's ribbon, number for number
  -- (`px_hold/lib/px_ninja_star.lua:126`): seven points, one per game frame,
  -- half the module's default width, grey. The ripper's stars should read as
  -- the same shuriken, so the request's trail is reused rather than re-tuned.
  -- The points are sampled a frame apart at 45 px/frame, so the ribbon is
  -- ~4x the thrown star's length; `max` is the dial if that is too much.
  local TRAIL = { max = 7, every = 1, core_w = 4.0, glow_w = 7.0, r = 120, g = 120, b = 120 }

  local function current_worm()
    for _, w in ipairs(wa.worms.all()) do
      if w.turn then return w end
    end
  end

  -- The star's speed at the impact. WA destroys the missile on the frame it
  -- hits, so `on_explode` cannot read it; keep the last frame's (the Javelin's
  -- own note). Also the source of the stick orientation.
  local speed = {}
  wa.on.missile_frame(function(m)
    if m.weapon ~= "px.ripper_star" then return end
    speed[m.id] = { m.vx, m.vy }
    -- The first frame the missile exists is the start of its flight; WA
    -- launches these itself, so there is no `wa.weapons.launch` return value
    -- to hand `trail.add` (as the ninja star's handler does,
    -- `px_hold/lib/px_ninja_star.lua:145-151`).
    if m.phase == "pre" and not trail.has(m.id) then
      trail.add(m.id, current_worm(), TRAIL)
    end
  end)

  -- The star in flight: PX's `ldata->anim.spriteIndex = 0` hides WA's missile
  -- and a follower actor draws the 32-orientation sheet.
  sb.flight(ctx, {
    weapon = "px.ripper_star",
    sheet = ART .. "stamp",
    anim = "none",
    frame_fn = function(m) return orientation(m.vx, m.vy) end,
    z = wa.depth.OBJECTS - 1,
    mirror = false,
  })

  -- PX's hold: the Ripper gun, hands baked into the 90x90 cell, so no hand
  -- sheet and `draw_hand = false` (`ripper_script.txt:173`).
  --
  -- The engine's `spec.hold` draws the aiming frames, including its
  -- `grow()` pick animation (`worm_hold.rs:121-135, :351-355`; PX's
  -- `scale_pick`, `worms_anims_script.txt:231-258`). Its firing branch needs
  -- `h.firing`, which only the turn's fire message sets (`worm_hold.rs:139-145,
  -- :251-266`), so on a held burst it drops the sheet from the second shot's
  -- firing frames (0x6A/0x6B). `lib/px_hold_art.lua` covers just those two
  -- states at full size, which is PX's firing branch (`:280-283`). The engine's
  -- hold band (`worm_hold.rs:18`) is PX's zplane 4 (`:174`) in practice.
  -- `weap_rotation = 1.0` (PX's own, `:171`) gives the barrel-up angle
  -- `PI - PI * aim` (`worm_hold.rs:346, :365`).
  local hold = {
    weapon = "px.ripper_star",
    sheet = ART .. "hold",
    size = 90,
    keep_while_firing = false,
    weap_rotation = 1.0,
    weap_radial_rotation = 1.0,
    weap_radius = 0.0,
  }

  local spec = {
    wep = "weps/ripper_star_wep.wep",
    panel_icon = ART .. "icon.png",
    sprites = { ART .. "stamp", ART .. "hold", trail.BEAM, trail.GLOW },
    params = { gpu_prefix = "sprites/" },
    worm_sprites = sb.PX_POSTURE,
    hold = hold,
    sounds = { SND .. "impact.wav" },

    -- The burst. PX rebuilds `Desc` from the worm every `FireFinal` and lets
    -- the up/down keys move `rgFA` through the burst (:96-99), so the angle is
    -- read from the worm at each shot, never frozen at the first one. The
    -- position and facing are live for the same reason.
    on_fire = function(ev)
      local w = ev.worm
      -- The base holds worm.shots_fired/shots_to_fire, so the worm keeps its
      -- firing stance and does not retreat until the last shot has left. WA's
      -- muzzle is `CTX_SPAWN_X/Y`, the engine's computed shot point
      -- (`crates/engine/src/actor.rs:870-889`). Keep its distance from the
      -- worm, but apply it with the worm's current facing on every shot: a
      -- script can turn the worm during the burst, and PX re-applies
      -- `2 * TurnSide` every loop (`ripper_fire.txt:18`), so a captured signed
      -- x would leave the rest of the burst firing from the old side.
      local ox = math.abs(ev.x - w.x)
      local oy = ev.y - w.y
      local function angle(i, ww)
        -- PX's M_FRAME wobble (:96-98): i is 1-based, RSShotsFired is 0-based.
        local n = i - 1
        local base = ww.aim
        if n & 2 ~= 0 then return base - 0.010 end
        if n & 3 ~= 0 then return base + 0.010 end
        return base
      end
      seq.fire_seq_mis({
        weapon = "px.ripper_star",
        -- End the burst if the worm is knocked out of its firing state (a
        -- blast, a push, a teleport); see `lib/fire_seq.lua`.
        cancel_weapon = "px.ripper_star",
        -- The muzzle sits 3.4 px above the worm's centre, inside its ~6 px
        -- collision circle, so a star spawned there bursts on the owner at
        -- once. Push every star 12 px along its own launch direction, exactly
        -- as the laser draws its beam from 24 px out (`laser_gun.lua:53`);
        -- PX's offsets above are kept and this is added.
        standoff = 12,
        owner = w,
        count = SHOTS,
        delay = SHOT_DELAY,
        x = function(i, ww)
          local low = ww.aim < LOW_AIM and 2.0 or 0
          return ww.x + ww.facing * (ox + low)
        end,
        y = function(i, ww)
          return ww.y + oy - 3.4 - (ww.aim < LOW_AIM and 3.1 or 0)
        end,
        vx = function(i, ww)
          local d = 0.5 - angle(i, ww)
          return ww.facing * (0.5 - math.sqrt(d * d)) * SPEED
        end,
        vy = function(i, ww)
          return SPEED * (0.5 - angle(i, ww))
        end,
      })
    end,

    -- PX's impact, after the record's own (zero) blast.
    on_explode = function(ev)
      local v = speed[ev.missile]
      if ev.missile then speed[ev.missile] = nil; trail.drop(ev.missile) end
      local vx, vy = v and v[1] or 0, v and v[2] or 0

      -- The first eligible object in the square, in the engine's object order
      -- (PX scans `Env->Objs` in its order too).
      local target
      for _, o in ipairs(wa.world.electrical_nearby(ev.x, ev.y, 29, false)) do
        if (o.kind == "worm" or o.kind == "mine" or o.kind == "crate" or o.kind == "oil")
          and within(o, ev.x, ev.y, HIT_R) then target = o break end
      end
      if not target then
        local active = current_worm()
        if within(active, ev.x, ev.y, SELF_R) then target = active end
      end
      if target then
        if target.kind == "worm" then
          -- PX's two effects as one: 4 damage and a quarter of the star's
          -- speed as a shove. `worm:hurt{ vx, vy }` puts the speed in the
          -- hit's force fields, where PX's own `M_GUNEXP` put its force
          -- (`contributing-with-an-agent.md:66`); WA then throws the worm and
          -- commits the health when it lands. PX instead wrote the worm's
          -- memory (`target->SpX = SpX/4`) and posted the hit separately --
          -- a raw field write that does not commit damage on 3.8.1.
          target:hurt{ amount = DAMAGE, vx = trunc(vx / 4), vy = trunc(vy / 4) }
        else
          -- A crate or oil drum: PX's `M_GUNEXP` force (half the star's
          -- speed, `:108`), through WA's own hit.
          target:hit(DAMAGE, trunc(vx / 2), trunc(vy / 2), "projectile")
        end
        return
      end

      -- No target: stick the star in the land and play PX's impact sound.
      wa.land.stamp{ sprite = ART .. "stamp", frame = orientation(vx, vy),
        x = ev.x, y = ev.y, buried = BURIED }
      local shooter = current_worm()
      if shooter then wa.sound.play(shooter, SND .. "impact.wav") end
    end,
  }
  -- PX's records carry the turn off (byte +0x18 = 1); say so explicitly, as
  -- the ninja star's port does.
  spec.handling = { ends_turn = true }
  hold_art.add(hold)
  wa.weapons.replace(spec)
end

return M
