-- Highlander: Valyrian Fire (PX weapon_valyrianfire, rafa``2's valyrianfire_s).
local shared = require("lib/shared")
local fires = shared.fires

-- PX's FireFinal: from a worm in the water nothing is thrown and the bottle
-- goes back into the team's ammo; otherwise the bottle starts 15 pixels
-- further along the aim. WA's own projectile from there, so WA flies, burns
-- and explodes it as its Petrol Bomb.
local THROW_OUT = 15

fires.valyrian_fire = function(fire)
  local w = fire.worm
  if w.y >= wa.world.water() then
    -- Set, as the pack always writes ammo; infinite (-1) stays infinite.
    local n = w:ammo("petrol_bomb")
    if n >= 0 then w:ammo("petrol_bomb", { set = n + 1 }) end
    return
  end
  -- Along the aim, which is the throw's direction. Not PX's cos and sin of
  -- the aim angle: the start is simulation, and only sqrt is exact on
  -- every machine.
  local x, y = fire.x, fire.y
  local speed = math.sqrt(fire.vx * fire.vx + fire.vy * fire.vy)
  if speed > 0 then
    x = x + math.floor(THROW_OUT * 0x10000 * fire.vx / speed)
    y = y + math.floor(THROW_OUT * 0x10000 * fire.vy / speed)
  end
  wa.weapons.launch({ weapon = "petrol_bomb", owner = w, x = x, y = y, vx = fire.vx, vy = fire.vy })
end

-- PX's ExplodeAt: 51 fires on a 3-pixel ring at the impact, besides WA's own
-- explosion (the record starts no fire of its own: its detonation is 0). Each
-- with PX's CFireDesc: count 0, duration 6000, no upward power, damage 0,
-- owned by the team of the worm whose turn it is. PX's worm handler makes
-- their hits 25% more damaging and knocks twice as hard (its M_GUNEXP,
-- WA's 0x4B from the fire): the engine scales them as it spawns them. PX
-- draws them green, SetColorMod(RGB(75, 225, 75)): `tint`, on the GPU.
--
-- PX places them at x +- 3 cos(360 - 7.2 i), y - 3 sin(360 - 7.2 i), the sign
-- of x alternating. Simulation, so not computed here: the offsets below are
-- that formula's, 16.16, worked out once (cos and sin need not agree to the
-- bit between machines; integers do).
local RING_DX = {
    -55776, -115699, 196548, -123441, -46357, 179843, -172459, 29988, 135973, -195426,
    101803, 71562, -188873, 158240, -3658, -153789, 190774, -78326, -95475, 194490,
    -141162, -22738, 168827, -182674, 53433, 117662, -196593, 121533, 48723, -180815,
    171275, -27575, -137724, 195144, -99709, -73828, 189536, -156780, 1219, 155297,
    -190169, 76083, 97599, -194832, 139453, 25159, -170064, 181759, -51082, -119607,
    196608,
}
local RING_DY = {
    -188531, -158960, -4877, 153027, 191065, 79442, -94407, -194308, -142008, 21527,
    168199, 183122, 54606, -116683, -196574, -122489, 47541, 180333, 171870, 28782,
    -136851, -195289, -100758, 72697, 189208, 157513, 2439, -154546, -190475, -77206,
    96539, 194665, 140310, -23949, -169449, -182220, -52259, 118637, 196604, 120572,
    -49904, -181290, -170673, -26368, 138591, 194992, 98656, -74957, -189856, -156041,
    0,
}
local VALYRIAN_FIRE = {
  count = 0, duration = 6000, up_power = 0, damage = 0, damage_scale = 1.25, knock_scale = 2,
  tint = 0x4BE14B,
}

fires.valyrian_burst = function(ev)
  local owner = shared.current_worm() or ev.worm
  if not owner then return end
  for i = 1, #RING_DX do
    wa.fire.spawn({
      owner = owner, x = ev.x + RING_DX[i], y = ev.y + RING_DY[i],
      count = VALYRIAN_FIRE.count, duration = VALYRIAN_FIRE.duration,
      up_power = VALYRIAN_FIRE.up_power, damage = VALYRIAN_FIRE.damage,
      damage_scale = VALYRIAN_FIRE.damage_scale, knock_scale = VALYRIAN_FIRE.knock_scale,
      tint = VALYRIAN_FIRE.tint,
    })
  end
end
