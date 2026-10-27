-- px_hold_art.lua -- draw a held weapon during WA's repeated-fire frames.
--
-- Why this exists
-- ---------------
-- The engine's `spec.hold` owns the hold in every state it can: aiming
-- (0x67-0x69) with PX's grow-in pick animation, the put-away, and the firing
-- states when `h.firing` is set. `h.firing` comes from
-- `worm_hold::on_fire` on MSG_FIRE_WEAPON alone (`crates/engine/src/worm_hold.rs:139-145`,
-- called from `crates/engine/src/physics.rs:1243`). A burst that holds
-- `shots_fired`/`shots_to_fire` (`lib/fire_seq.lua`) makes WA fire the slot
-- again from its own loop, with no new fire message, so from the second shot
-- on `h.firing` is false: the firing frames (0x6A/0x6B) hide the sheet while
-- the aiming frames still show it. The gun blinks once per repeated shot.
--
-- This module draws only those two firing frames, through the same GPU queue
-- and at the same depth and transform. It is presentation only: it runs inside
-- `wa.on.draw`, reads worm state, and enqueues `wa.draw.quad`; it writes
-- nothing to the simulation and uses no clock or random number.
--
-- PX's firing branch sets `counter = 18` and `scale_pick = scale` before it
-- draws (`worms_anims_script.txt:280-283`), so the firing cell is always at
-- full size; there is no pick animation to reproduce here.
--
-- The transform is `worm_hold::draw` / `place`
-- (`crates/engine/src/worm_hold.rs:337-370, :268-300`) as `render::Sprite`
-- emits it (`crates/render/src/geom.rs:49-111`):
--
--   aim      0 straight down .. 1 straight up
--   rot      (1 - aim) * PI
--   centre   worm position + radial offset along rot
--   angle    (PI - PI*aim - PI*(1 - weap_rotation)) * facing, degrees clockwise
--   scale    1.0 -- PX's firing branch, `worms_anims_script.txt:283`
--   mirror   facing < 0
--
-- A quad carries the sheet's top-left at its first point and its corners
-- clockwise, so a mirrored sheet is drawn by giving the texture's top-left
-- the mirrored corner (a left/right swap of the point order), exactly as
-- `geom.rs:95-111` swaps the cell's x box and `u0/u1`.

local M = {}

-- `worm_hold::visible`'s firing branch, by raw WA state (`worm_state.rs:30-34`).
-- The labels cannot be used here: `worm.state` returns nil for several raw
-- states because `worm_state_name` only names the states whose setup it
-- reproduces (`crates/lua-host/src/actor.rs:2189-2207`), while `state_id` is
-- the raw value even when it has no name (`:1469-1475`).
-- Aiming deliberately is not listed: the engine's `spec.hold` draws it,
-- including the pick animation (`worm_hold.rs:121-135, :351-355`).
local FIRING = {
  [0x6A] = true, -- firing
  [0x6B] = true, -- fired
}

-- `worm_hold::DEPTH`: the engine's one front band (`worm_hold.rs:18`).
local DEPTH = 0x10000

local draws = {}
local hooked = false

-- One quad spec, refilled per draw: `wa.draw.quad` copies its table into the
-- frame's draw list (the same reason the effects SDK trail reuses its ribbon table),
-- so no table is made inside the render callback.
local QUAD = { depth = DEPTH, points = { {}, {}, {}, {} } }

-- `render::Sprite::emit`'s rotation: angle in radians, clockwise, y down.
local function corner(t, cx, cy, cos, sin, lx, ly)
  t.x = cx + lx * cos - ly * sin
  t.y = cy + lx * sin + ly * cos
end

-- `w.aim`/`w.facing` are read on every frame, never captured: vanilla lets the
-- player micro-adjust the aim through a burst and a script can flip the worm,
-- and PX's `FireFinal` rebuilds its shot from that live state each loop. The
-- engine's own hold uses `live_aim` while aiming for the same reason
-- (`crates/engine/src/worm_hold.rs:338-344`).
local function enqueue(art, w)
  local pi = math.pi
  local facing = w.facing < 0 and -1 or 1
  local aim = w.aim

  local rot = (1.0 - aim) * pi
  local rot_w = rot + pi * art.weap_radial_rotation
  local cx = w.x + facing * wa.math.sin(rot_w) * art.weap_radius
  local cy = w.y - wa.math.cos(rot_w) * art.weap_radius
  local angle = (pi - pi * aim - pi * (1.0 - art.weap_rotation)) * facing
  local cos, sin = wa.math.cos(angle), wa.math.sin(angle)

  local half = art.size * 0.5
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
  QUAD.sprite = art.sheet
  wa.draw.quad(QUAD)
end

local function hook()
  hooked = true
  wa.on.draw(function()
    for i = 1, #draws do
      local art = draws[i]
      for _, w in ipairs(wa.worms.all()) do
        -- `draw_holds` skips dead, hidden and body-hidden worms
        -- (`worm_hold.rs:309-315`); `visible`/`body_visible` are the same two
        -- hide flags (`crates/lua-host/src/actor.rs:1523-1541`).
        local st = w.state_id
        if w.hp and w.hp > 0 and w.visible and w.body_visible
            and w.weapon == art.weapon and st and FIRING[st] then
          enqueue(art, w)
        end
      end
    end
  end)
end

-- `art` is the same table the weapon also passes as `spec.hold`: `weapon` (the
-- id WA's `worm.weapon` reports), `sheet`, `size` (the cell, 90 for PX's gun
-- cells), and the engine's `weap_radius`/`weap_rotation`/`weap_radial_rotation`.
-- The engine ignores the two presentation-only keys (`weapon`, `size`).
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
