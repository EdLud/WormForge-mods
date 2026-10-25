-- Specialists' Bulldozer (PX weapon_bulldozer_yellow: PushBldzr_yellow.txt and
-- bulldozer_spb.txt): a walking digger. The newest one cuts a 10-pixel hole
-- just above itself every frame; every Bulldozer shoves what it touches.
local holds = require("wf-lib/holds")
local weapon = {}

weapon.definition = {
  -- PX's record from the Specialists scheme, byte for byte: WA's walking
  -- animal (the Skunk's slot), roaming, fused and fire-bursting.
  wep = "weps/bulldozer.wep",
  name = "Bulldozer",
  panel_icon = "sprites/bulldozer/bdico.png",
  sprite = "sprites/bulldozer/bd.png",
  worm_sprites = holds.PX_POSTURE,
  -- bulldozer_spb's CWormAnimParams.
  hold = {
    sheet = "sprites/bulldozer/bd.png", frames = 20,
    hand = holds.PX_HANDS[1], hand_type = 1, hand_scale = 0.8,
    hand_radius = 28, hand_rotation = -1, hand_radial_rotation = 1.1,
    weap_radius = 16, weap_rotation = 0.3, weap_radial_rotation = 1.1,
  },
}

-- PX's PUSH_COLMASK_YELLOW: a 20x20 box on the Bulldozer, checked against the
-- API's body circles (worm 6, mine 5, crate and oil drum 9 pixels).
local HALF = 10
local RADIUS = { worm = 6, mine = 5, crate = 9, oil = 9 }
-- bullProcessCollision(15.0): 0.6 * sqrt(Speed) pixels a frame, away from it.
local FORCE = 0.6 * math.sqrt(15)

-- The push: the box touches the body circle, and the direction from the
-- Bulldozer to it (none when they share a centre, as PX's dist > 0).
local function push_of(m, obj, r)
  local dx, dy = obj.x - m.x, obj.y - m.y
  local rx, ry = math.max(0, math.abs(dx) - HALF), math.max(0, math.abs(dy) - HALF)
  local d = math.sqrt(dx * dx + dy * dy)
  if rx * rx + ry * ry > r * r or d == 0 then return nil end
  return FORCE * dx / d, FORCE * dy / d
end

function weapon.setup()
  local current_worm = require("lib/shared").current_worm
  -- PX's dmis_bldzr: only the most recently fired Bulldozer digs. Missile ids
  -- count up in the order WA builds them, the same on every peer.
  local newest = 0
  wa.on.missile_frame(function(m)
    if m.weapon ~= "px.bulldozer" or m.phase ~= "pre" then return end
    if m.id > newest then newest = m.id end
    if m.id == newest then
      wa.land.cut({ x = m.x, y = m.y - 8.7, shape = "circle", radius = HALF })
    end
    -- PX sends each touched worm, oil drum, mine and crate its M_GUNEXP:
    -- flag 0, 1 damage, the push, no team. The turn's worm is spared.
    -- (PX also pushes fire, which has no hit here.)
    local turn = current_worm()
    for _, w in ipairs(wa.worms.all()) do
      if w.hp > 0 and not (turn and w.id == turn.id) then
        local vx, vy = push_of(m, w, RADIUS.worm)
        if vx then w:hurt({ amount = 1, vx = vx, vy = vy }) end
      end
    end
    for _, kind in ipairs({ "mine", "crate", "oil" }) do
      local all = kind == "mine" and wa.mines.all() or kind == "crate" and wa.crates.all() or wa.oil.all()
      for _, o in ipairs(all) do
        local vx, vy = push_of(m, o, RADIUS[kind])
        if vx then o:hit(1, vx, vy) end
      end
    end
  end)
end

return weapon
