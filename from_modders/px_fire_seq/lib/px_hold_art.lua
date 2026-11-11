-- Draw a held weapon during WA's repeated-fire frames (0x6A/0x6B).

local M = {}

local FIRING = {
  [0x6A] = true, -- firing
  [0x6B] = true, -- fired
}

local DEPTH = 0x10000

local draws = {}
local hooked = false

local QUAD = { depth = DEPTH, points = { {}, {}, {}, {} } }

local function corner(t, cx, cy, cos, sin, lx, ly)
  t.x = cx + lx * cos - ly * sin
  t.y = cy + lx * sin + ly * cos
end

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
    local weapons = {}
    local worms = wa.worms.all()
    for j = 1, #worms do weapons[j] = worms[j].weapon end
    for i = 1, #draws do
      local art = draws[i]
      for j = 1, #worms do
        if weapons[j] == art.weapon then
          local w = worms[j]
          local st = w.state_id
          if st and FIRING[st] and w.hp and w.hp > 0 and w.visible and w.body_visible then
            enqueue(art, w)
          end
        end
      end
    end
  end)
end

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
