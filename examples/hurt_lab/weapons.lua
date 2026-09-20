-- Fire punch is only the panel slot. Space is lockstep FIRE_WEAPON.
-- "Eat" stops the firepunch stock attack and animation to happen to be able to make your custom firepath timing.
-- First Eat stops the firepunch attack from happening even when you have 0 firepunch ammo, this is because you could still use this weapon with 0 firepunch in scheme and we want it to still work.

local line = "ten  Space = 10 hp each enemy"

wa.weapons.replace({
  weapon = "fire_punch",
  name = "Ten",
  is_weapon = true,
})

wa.on.worm_message(function(worm, msg)
  if msg ~= wa.msg.FIRE_WEAPON then
    return
  end
  if worm.weapon ~= "fire_punch" then
    return
  end
  local ammo = worm:ammo("fire_punch")
  if ammo == 0 then
    return "eat"
  end
  if ammo > 0 then
    worm:ammo("fire_punch", -1)
  end
  for _, w in ipairs(wa.worms.all()) do
    if w.alliance ~= worm.alliance and w.hp > 0 then
      w:hurt(10)
    end
  end
  return "eat"
end)

wa.on.hurt(function(hit)
  if hit.phase ~= "post" or hit.lost < 1 then
    return
  end
  line = hit.kind .. " -" .. tostring(hit.lost) .. " hp"
  wa.log(line)
end)

wa.on.hud(function()
  wa.hud.line(line)
end)
