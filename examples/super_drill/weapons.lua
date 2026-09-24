-- PX Super Drill keeps WA's normal drilling state and adds a second cut at
-- the worm's position each frame. See PX weapon_super_drill.pxl.

local watching = {}
local START_GRACE = 4

local function follow_stock_drill(worm, id)
  local started = false
  local waiting = 0
  return function(a)
    if worm.drilling then
      started = true
      wa.land.cut({ x = worm.x, y = worm.y, shape = "drill" })
      return
    end
    if not started and waiting < START_GRACE then
      waiting = waiting + 1
      return
    end
    watching[id] = nil
    a:despawn()
  end
end

wa.weapons.replace({
  weapon = "pneumatic_drill",
  name = "Super Drill",
  copy_from = "pneumatic_drill",
  is_weapon = true,
})

wa.on.worm_message(function(worm, msg)
  if msg ~= wa.msg.FIRE_WEAPON or worm.weapon ~= "pneumatic_drill" then
    return
  end
  -- Stock fire still owns ammo, movement, sound, animation and random cuts.
  if worm:ammo("pneumatic_drill") == 0 or watching[worm.id] then
    return
  end
  local id = worm.id
  watching[id] = wa.actors.spawn({
    sprite = false,
    x = worm.x,
    y = worm.y,
    gravity = false,
    collide = false,
    owner = worm,
    on = follow_stock_drill(worm, id),
  })
  -- Do not eat FIRE_WEAPON: WA must enter its normal drilling state.
end)
