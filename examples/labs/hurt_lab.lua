-- Ten: built on WA's Fire Punch, wherever it is placed. Space is lockstep
-- FIRE_WEAPON. "Eat" stops the stock punch and its animation, so a pack can
-- time its own fire path. It eats even with 0 ammo, as a scheme may give
-- the weapon none and this should still work.
return {
  install = function()
    local line = "ten  Space = 10 hp each enemy"

    local TEN = "labs.hurt_lab"

    wa.weapons.replace({
      copy_from = "stock.fire_punch",
      name = "Ten",
      is_weapon = true,
    })

    wa.on.worm_message(function(worm, msg)
      if msg ~= wa.msg.FIRE_WEAPON then
        return
      end
      if worm.weapon ~= TEN then
        return
      end
      local ammo = worm:ammo(TEN)
      if ammo == 0 then
        return "eat"
      end
      if ammo > 0 then
        worm:ammo(TEN, -1)
      end
      for _, w in ipairs(wa.worms.all()) do
        if w.alliance ~= worm.alliance and w.hp > 0 then
          w:hurt(10)
        end
      end
      return "eat"
    end, { msgs = { wa.msg.FIRE_WEAPON } })

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
  end,
}
