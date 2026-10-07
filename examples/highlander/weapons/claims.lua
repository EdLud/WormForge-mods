-- Highlander: the slot claims. Split from rules.lua by tools/split_highlander.py.
local shared = require("lib/shared")
local PORTED = shared.PORTED
local PX_ART = shared.PX_ART
local PX_HOLDS = shared.PX_HOLDS
local WEP_NAME = shared.WEP_NAME
local WEP_PATCH = shared.WEP_PATCH
local fires = shared.fires

-- WA's muzzle can be inside a wall when a worm fires from beside it. A stock
-- Old Woman constructed there explodes before her first frame. Dispatch the
-- shot to Lua so she can be launched from a clear point the worm can see,
-- keeping WA's own Old Woman movement and five-second fuse.
local OLD_WOMAN_LAUNCHER_PATCH = {
  uses_turn = 0,
  subtype_param = 3, -- bazooka aim sheet, not the Sheep Launcher hold
  fire_type = 1,
  fire_method = 3, -- CreateWeaponProjectile, intercepted by on_fire
}

-- Our own changes over the generated record patches (tools/embed_weps.py),
-- kept here so WEP_PATCH can be generated again.
local PATCH_FIXES = {
  -- S.M.A.R.T Bomb: homing bits leave the bomb's red trail circles (stock 250,
  -- drawn as sprites/smart_bomb/trail), not WA's green gas cloud (608) the
  -- record named.
  mortar = { c_homing_sprite = 250 },
}

for _, list in ipairs({ PORTED, PX_ART }) do
  for _, w in ipairs(list) do
    -- copy_from + name + named patch (stock base); was weps/<slot>.wep
    local spec = w.wep and { wep = w.wep } or { copy_from = w.weapon, name = WEP_NAME[w.weapon] }
    if w.weapon == "old_woman" then
      spec.patch = OLD_WOMAN_LAUNCHER_PATCH
      spec.on_fire = function(fire) fires.old_woman(fire) end
    elseif not w.wep and WEP_PATCH[w.weapon] then
      spec.patch = WEP_PATCH[w.weapon]
    end
    if PATCH_FIXES[w.weapon] then
      local patch = {}
      for k, v in pairs(spec.patch or {}) do patch[k] = v end
      for k, v in pairs(PATCH_FIXES[w.weapon]) do patch[k] = v end
      spec.patch = patch
    end
    for key, value in pairs(w) do
      spec[key] = value
    end
    spec.hold = PX_HOLDS[w.weapon]
    wa.weapons.replace(spec)
  end
end

do
  -- reddaz's launch point search, playtested by him. A point is clear when
  -- it and 8 points on a 3-pixel circle around it are free of land, and the
  -- worm can see it (nothing between them, so never the far side of a thin
  -- wall the muzzle poked through). The muzzle is tried first, then rings
  -- every 4 pixels out to 40, at finer angles the wider the ring; failing
  -- all, she starts at the worm.
  local P = 0x10000
  local CLEAR = 3 * P
  local REACH = 40 * P
  local RING = 4 * P

  local function clear(x, y)
    if wa.land.solid(x, y) then return false end
    for i = 0, 7 do
      local a = (i / 8) * 2 * math.pi
      if wa.land.solid(x + math.floor(CLEAR * wa.math.cos(a)), y + math.floor(CLEAR * wa.math.sin(a))) then
        return false
      end
    end
    return true
  end

  local function launch_point(x, y, w)
    local r = 0
    while r <= REACH do
      local step = (r == 0) and 360 or math.max(15, math.floor(360 / ((r / P) / 2)))
      local deg = 0
      while deg < 360 do
        local a = deg * math.pi / 180
        local tx, ty = x + math.floor(r * wa.math.cos(a)), y + math.floor(r * wa.math.sin(a))
        if clear(tx, ty) then
          local hit = wa.land.trace(tx, ty, w.x, w.y)
          if not hit or not hit.hit then return tx, ty end
        end
        deg = deg + step
      end
      r = r + RING
    end
    return w.x, w.y
  end

  fires.old_woman = function(fire)
    local w = fire.worm
    local x, y = launch_point(fire.x, fire.y, w)
    wa.weapons.launch({ weapon = "old_woman", owner = w,
      x = x, y = y, vx = fire.vx, vy = fire.vy, fuse = 5000 })
  end
end
