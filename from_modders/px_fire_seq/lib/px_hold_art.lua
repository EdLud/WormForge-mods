-- Draw a held weapon during WA's repeated-fire frames (0x6A/0x6B). The engine
-- draws the aiming and put-away frames; from the second shot of a held burst
-- `h.firing` is false, so this fills those two frames at full size. With a
-- second entry marked `flash = true` (PX's firing sheet) that art replaces the
-- hold for the frames around each shot instead of for the whole burst.
-- Presentation only: reads worm state and enqueues quads.

local M = {}

-- Raw WA states; `worm.state` is nil for some of them.
local FIRING = {
  [0x6A] = true, -- firing
  [0x6B] = true, -- fired
}

-- `worm_hold::DEPTH`: the engine's one front band (`worm_hold.rs:18`).
local DEPTH = 0x10000

-- The engine's hand cells (`sprites/px_hold/hand_rad*`): what the hand quad
-- measures when the caller does not give `hand_size`.
local HAND_CELL = 60

local draws = {}
local hooked = false

-- One quad spec, refilled per draw: no table in the render callback.
local QUAD = { depth = DEPTH, points = { {}, {}, {}, {} } }

-- A row of `art.flash` (PX's firing sheet) shows only in the frames around a
-- shot. WA's 0x6A/0x6B pair is one shot's animation, so two 50 Hz frames cover
-- it without lighting the whole gap between burst shots.
local FLASH_FRAMES = 2
-- Worm id -> `wa.world.frame()` of its last shot.
local shot_at = {}
-- Worm id -> the frame its firing art was last drawn on. The simulation can
-- skip frames between two draws, so a shot also lights the first draw that
-- follows it and never flashes for zero frames.
local drawn_at = {}

local function firing_now(art, w, now)
  -- A burst's own sequencer marks its shots and the weapon passes that table as
  -- `shots`. It is deliberately not required here: an exported module is
  -- instanced per consuming pack, so `require("wf-lib/fire_seq")` in this file
  -- can be a different instance from the one firing the weapon.
  local f = shot_at[w.id]
  local g = art.shots and art.shots[w.id]
  if g and (not f or g > f) then f = g end
  if not f then return false end
  local seen = drawn_at[w.id]
  return now - f < FLASH_FRAMES or seen == nil or seen < f
end

-- A weapon can mark a shot itself: a custom `on_fire`, a scripted shot, or a
-- single shot WA fires (the helper then lights only that frame's draws).
function M.shot(w)
  if w and w.id then shot_at[w.id] = wa.world.frame() end
end

-- `render::Sprite::emit`'s rotation: angle in radians, clockwise, y down.
local function corner(t, cx, cy, cos, sin, lx, ly)
  t.x = cx + lx * cos - ly * sin
  t.y = cy + lx * sin + ly * cos
end

local function quad(sheet, cx, cy, angle, half, facing, frame)
  local cos, sin = wa.math.cos(angle), wa.math.sin(angle)
  local pts = QUAD.points
  if facing < 0 then
    corner(pts[1], cx, cy, cos, sin, half, -half) -- texture top-left on the right
    corner(pts[2], cx, cy, cos, sin, -half, -half)
    corner(pts[3], cx, cy, cos, sin, -half, half)
    corner(pts[4], cx, cy, cos, sin, half, half)
  else
    corner(pts[1], cx, cy, cos, sin, -half, -half)
    corner(pts[2], cx, cy, cos, sin, half, -half)
    corner(pts[3], cx, cy, cos, sin, half, half)
    corner(pts[4], cx, cy, cos, sin, -half, half)
  end
  QUAD.sprite = sheet
  QUAD.frame = frame or 0
  wa.draw.quad(QUAD)
end

-- The engine's own phase (`worm_hold.rs:140`): `anim_speed * 0.03` per 50 Hz
-- frame, so a strip animates at the same rate here. `h.phase` is not readable,
-- so the world clock stands in for it; only the starting frame can differ, and
-- that is invisible on a loop.
local function gun_frame(art)
  local frames = art.frames or 1
  if frames <= 1 then return 0 end
  local now = wa.world.frame() or 0
  local phase = now * (art.anim_speed or 1) * 0.03
  return math.floor((phase % 1) * frames) % frames
end

-- Read aim and facing live: the player can adjust them mid-burst.
local function enqueue(art, w)
  local pi = math.pi
  local facing = w.facing < 0 and -1 or 1
  local aim = w.aim

  local rot = (1.0 - aim) * pi
  local rot_w = rot + pi * art.weap_radial_rotation
  local cx = w.x + facing * wa.math.sin(rot_w) * art.weap_radius
  local cy = w.y - wa.math.cos(rot_w) * art.weap_radius
  local angle = (pi - pi * aim - pi * (1.0 - art.weap_rotation)) * facing
  quad(art.sheet, cx, cy, angle, art.size * 0.5, facing, gun_frame(art))

  -- The hand rides the same aim, as `worm_hold::draw_holds` does: it sits on
  -- the other radial (`rot_h = rot - PI * hand_radial_rotation`) and is drawn
  -- after the gun so it covers the grip. Without this the hand disappears for
  -- the whole burst, because the engine only draws it in the aiming states.
  if art.hand and art.draw_hand ~= false then
    local hand_radius = art.hand_radius or 0
    if hand_radius ~= 0 then
      local rot_h = rot - pi * (art.hand_radial_rotation or 1)
      local hx = w.x + facing * wa.math.sin(rot_h) * hand_radius
      local hy = w.y - wa.math.cos(rot_h) * hand_radius
      local hand_angle = (rot + pi * (art.hand_rotation or 1)) * facing
      local size = (art.hand_size or HAND_CELL) * (art.hand_scale or 1)
      quad(art.hand, hx, hy, hand_angle, size * 0.5, facing, 0)
    end
  end
end

local function hook()
  hooked = true
  wa.on.draw(function()
    -- The worms are read once a draw: each field read is a call into the
    -- engine, and the draw runs every rendered frame.
    local now = wa.world.frame() or 0
    local worms = wa.worms.all()
    for j = 1, #worms do
      local w = worms[j]
      local st = w.state_id
      -- `draw_holds` skips dead, hidden and body-hidden worms
      -- (`worm_hold.rs:309-315`); `visible`/`body_visible` are the same two
      -- hide flags (`crates/lua-host/src/actor.rs:1523-1541`).
      if st and FIRING[st] and w.hp and w.hp > 0 and w.visible and w.body_visible then
        local weapon = w.weapon
        if weapon ~= nil then
          -- The plain hold fills the firing frames; a `flash` sheet lights over
          -- it only around the shot itself, as PX's `OnFiringAnim(isFiring)`.
          for i = 1, #draws do
            local art = draws[i]
            if art.weapon == weapon and (not art.flash or firing_now(art, w, now)) then
              enqueue(art, w)
            end
          end
          drawn_at[w.id] = now
        end
      end
    end
  end)
end

-- `art` is the same table the weapon also passes as `spec.hold`: `weapon` (the
-- id WA's `worm.weapon` reports), `sheet`, `size` (the cell, 90 for PX's gun
-- cells), and the engine's `weap_radius`/`weap_rotation`/`weap_radial_rotation`.
-- `frames`/`anim_speed` animate the strip here as the engine does. The hand keys
-- (`hand`, `hand_radius`, `hand_rotation`, `hand_radial_rotation`, `hand_scale`,
-- and the presentation-only `hand_size`) are drawn too.
-- `flash = true` makes the entry a firing sheet: it only shows on the frames
-- around a shot (`M.shot`, or `shots` — a sequencer's own shot table), never
-- for a whole burst.
-- The engine ignores the presentation-only keys: weapon, size, hand_size, flash.
function M.add(art)
  if type(art) ~= "table" or not art.sheet or not art.weapon then
    wa.log("px_hold_art: a hold needs a sheet and a weapon id")
    return
  end
  if not (wa.on and wa.on.draw and wa.draw and wa.draw.quad) then
    wa.log("px_hold_art: this build has no wa.on.draw/wa.draw.quad")
    return
  end
  art.size = art.size or 90.0
  art.weap_radius = art.weap_radius or 0.0
  art.weap_rotation = art.weap_rotation or 1.0
  art.weap_radial_rotation = art.weap_radial_rotation or 1.0
  draws[#draws + 1] = art
  if not hooked then hook() end
end

return M
