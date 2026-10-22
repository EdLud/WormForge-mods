-- px_sprite_builder.lua -- PX's sprite builder, re-implemented for WormForge API 4.
--
-- Two jobs, ported from PX's sources:
--
--   1. Missile flight drawing (red_sprite_builder.txt): hide WA's sprite
--      (`m.sprite = 0`, PX's `ldata->anim.spriteIndex = 0` at :39) and follow the
--      missile with a GPU actor that turns with PX's animation types.
--
--   2. The shared worm-hold library at the foot of this file: PX's weapon-less
--      worm aim and pick posture (`def_shot_aim_{p,u,d}`, `default_pick_{p,u,d}`,
--      `worms_anims_script.txt:31-37`) as `PX_POSTURE`, and PX's three hands as
--      `PX_HANDS`. A weapon claims both -- `worm_sprites = sb.PX_POSTURE` draws
--      the worm, and `hold` draws its own single weapon PNG and hand over the
--      worm exactly as PX's builder does (`:670-726`,
--      `crates/engine/src/worm_hold.rs`). Hundreds of weapons share the one
--      library and bring only their own PNG; no 32-frame aim folders are cut.
--
-- The public wf.sdk library owns the joined posture/hand strips. Qualified
-- wf-lib/px asset paths keep them with this provider while weapon art stays
-- with the consuming bundle. Highlander's private match state is separate.
--
-- PX originals: PX_pending/p_sprite_builder/worms_anims_script.txt and
-- wklua_and_px/utils/red_sprite_builder.txt. The library and the single weapon
-- PNGs are cut by porting-analysis/tools/build_hold_library.py.
--
-- A component's file, and anything it requires, runs where `wa` does not exist
-- yet: this module is pure data at load and touches `wa` only in `sb.flight`.

local shared = require("holds")

local M = {}

-- ---------------------------------------------------------------------------
-- PX animation types (red_sprite_builder.txt:17-24).
-- ---------------------------------------------------------------------------
local ANIM_TYPE = {
  track = 2,
  rotation = 3,
  slow = 1,
  medium = 1,
  fast = 1,
  none = 5,
}
local ANIM_SPEED = { slow = 0.5, medium = 0.8, fast = 1.35 }

-- The worm whose turn it is -- PX's GetCurrentWorm().
local function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
  end
end

local function sign(n) return n > 0 and 1 or (n < 0 and -1 or 0) end

-- ---------------------------------------------------------------------------
-- Cyclical animation frame (PX SetCustomAnim, red_sprite_builder.txt:51-57,
-- :83-85): phase += anim_speed * 30 / 1000 per frame, wraps at 0.99.
-- Returns frame index in [0, num_frames) and the updated phase.
-- ---------------------------------------------------------------------------
function M.cyclical_frame(phase, anim_speed, num_frames)
  if not phase then phase = 0.0 end
  local spd = (anim_speed or 1.0) * 30 / 1000
  phase = phase + spd
  if phase > 0.99 then phase = 0.0 end
  local frame = math.floor(phase * num_frames) % num_frames
  return frame, phase
end

-- Angle a round should point along its flight (PX :73, track type).
function M.track_angle(vx, vy)
  return -wa.math.atan(vx, vy) - math.pi
end

-- Speed-based rotation turn (PX :77, rotation type).
function M.rotation_turn(prev_rot, vx, vy, spin)
  return (prev_rot or 0) + (spin or 1.0) * 0.5 * (vx * 0.15 + math.abs(vy) * 0.01 * sign(vx))
end

-- Steady spin turn (PX :75, slow/medium/fast types).
function M.spin_turn(prev_rot, vx, anim_speed)
  return (prev_rot or 0) + (anim_speed or 0.5) * 0.5 * sign(vx)
end

-- ---------------------------------------------------------------------------
-- Missile flight drawing.
-- ---------------------------------------------------------------------------
function M.flight(ctx, opts)
  if not opts or not opts.weapon or not opts.sheet then
    wa.log("px_sprite_builder.flight: weapon and sheet are required")
    return
  end

  local anim_type = ANIM_TYPE[opts.anim or "none"]
  local spin = opts.spin or 1.0
  local cyclical = opts.cyclical or 0
  local anim_speed = opts.anim_speed or 1.0
  local z = opts.z or 5.0
  local scale = opts.scale or 1.0
  local mirror = opts.mirror ~= false
  local owner = opts.owner
  local frame_fn = opts.frame_fn
  local turn_fn = opts.turn_fn

  local follow = {}
  local spin_ang = {}
  local cycl_phase = {}

  local function gone(id)
    return function(b)
      local f = follow[id]
      if f and f.seen then f.seen = false return end
      follow[id] = nil
      spin_ang[id] = nil
      cycl_phase[id] = nil
      b:despawn()
    end
  end

  wa.on.missile_frame(function(m)
    if m.weapon ~= opts.weapon then return end
    if m.phase == "pre" then
      m.sprite = 0 -- hide WA's sprite; ours is drawn below
      return
    end
    local f = follow[m.id]
    if not f then
      f = { actor = wa.actors.spawn({
        sprite = opts.sheet, x = m.x, y = m.y,
        gravity = false, collide = false,
        owner = owner or current_worm(), on = gone(m.id),
      }) }
      follow[m.id] = f
    end
    f.seen = true
    local b = f.actor
    b.x, b.y, b.vx, b.vy = m.x, m.y, 0, 0

    local rot = 0
    if turn_fn then
      rot = turn_fn(m, spin_ang[m.id])
      spin_ang[m.id] = rot
    elseif anim_type == 2 then
      rot = M.track_angle(m.vx, m.vy)
    elseif anim_type == 3 then
      rot = M.rotation_turn(spin_ang[m.id], m.vx, m.vy, spin)
      spin_ang[m.id] = rot
    elseif anim_type == 1 then
      local spd = ANIM_SPEED[opts.anim] or 0.5
      rot = M.spin_turn(spin_ang[m.id], m.vx, spd)
      spin_ang[m.id] = rot
    end

    local frame = 0
    if frame_fn then
      frame = frame_fn(m)
    elseif cyclical and cyclical > 0 then
      frame, cycl_phase[m.id] = M.cyclical_frame(cycl_phase[m.id], anim_speed, cyclical)
    else
      cycl_phase[m.id] = nil
    end

    b.facing = mirror and (m.vx < 0 and -1 or 1) or 1
    b:frame(frame)
    b:gfx({ angle = math.deg(rot) % 360, depth = z, scale = scale })
  end)
end

-- ---------------------------------------------------------------------------
-- The shared worm-hold library, and PX's hands.
--
-- PX's sprite builder draws the worm's aim and pick posture with **no weapon in
-- it** -- `def_shot_aim_{p,u,d}` and `default_pick_{p,u,d}`, the sheets PX ships
-- with the builder (`worms_anims_script.txt:31-37`) -- and then draws the weapon
-- and the hand on top, where its `CalculateAngle` puts them (:569-629).
--
-- WormForge splits the same two halves between the engine and the pack: the
-- engine draws WA's worm from the claim's `worm_sprites`, then draws
-- `spec.hold`'s weapon and hand over it (`crates/engine/src/worm_hold.rs`). The
-- hold's fields are PX's `CWormAnimParams` verbatim -- `weap_radius`,
-- `weap_rotation`, `weap_radial_rotation`, `hand_radius`, `hand_rotation`,
-- `hand_radial_rotation`, `hand_type`, `hand_scale` -- read straight by the
-- engine's `HoldSpec` (`crates/lua-host/src/api.rs`).
--
-- So a weapon built from this library is one PNG and two lines:
--
--   worm_sprites = sb.PX_POSTURE,          -- the worm, weapon-less
--   hold = {
--     sheet = ART .. "hold",               -- the weapon, alone, once
--     hand  = sb.PX_HANDS[2],
--     weap_radius = 11.0, weap_rotation = 1.0, ...
--   },
--
-- Hundreds of weapons share the one library and bring only their own PNG, which
-- the engine rotates and places. Nothing is pre-composited: `(32*3 + 10*3)`
-- frames per weapon would be the alternative.
--
-- One hold field is PX's own rule: `keep_while_firing` is false for all five
-- weapons here, because PX draws no weapon in `WS_FIRED` unless the weapon names
-- a firing sprite (`spriteFiring = Params->FSprite`, `worms_anims_script.txt:101`,
-- :121, :263) -- none of these five does, so his own `else` sets `sprite = 0`
-- (:419-422) -- and the engine has no firing sprite to draw in its place
-- (`HoldSpec`, `crates/weapons/src/overlay.rs:33-49`; ASSUMPTIONS A14).
-- ---------------------------------------------------------------------------

-- The weapon-less worm in the six poses `worm_sprites` names, and PX's three
-- hands (1 lower, 2 middle, 3 upper): px's library, from lib/holds.lua.
M.PX_POSTURE = shared.PX_POSTURE
M.PX_HANDS = shared.PX_HANDS

return M
