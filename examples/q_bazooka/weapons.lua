-- Q stock-selects bazooka. Space hold = power bar, release = shoot (native StartFiring / ReleaseWeapon).

local prev_q = {}

wa.on.worm_message(function(worm, msg)
  if msg ~= wa.msg.FRAME_FINISH then
    return
  end
  if not worm.turn then
    prev_q[worm.id] = false
    return
  end
  local q = wa.world.keys().q
  if q and not prev_q[worm.id] then
    if worm.weapon ~= "bazooka" then
      local ammo = worm:equip("bazooka")
      wa.log("Q equip bazooka ammo=" .. tostring(ammo))
    end
  end
  prev_q[worm.id] = q
end, { msgs = { wa.msg.FRAME_FINISH } })
