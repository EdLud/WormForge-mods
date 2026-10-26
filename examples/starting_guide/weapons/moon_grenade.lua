-- Moon Grenade: WA's Grenade with about a third of the gravity.
-- One burst in four also digs a crater.

return {
  -- The weapon's data. The profile's settings for it (the loader's
  -- Manage Weapon Panel) are laid over these, field by field.
  defaults = {
    ammo = { round_start = 3 },
  },

  install = function()
    local last_crater -- set by the simulation, shown by the HUD

    wa.weapons.replace{
      copy_from = "stock.grenade",
      missile = { gravity_pct = 35 },

      -- Simulation: runs on every player's machine at the same moment,
      -- so it may change the game and roll WA's dice.
      on_explode = function(ev)
        if wa.random(4) == 1 then
          wa.land.cut{ x = ev.x, y = ev.y, shape = "circle", radius = 40 }
          last_crater = ("%d, %d"):format(math.floor(ev.x), math.floor(ev.y))
          wa.log("crater at " .. last_crater)
        end
      end,
    }

    -- Drawing: runs on each machine when it draws a frame, so it only reads.
    wa.on.hud(function()
      if last_crater then
        wa.hud.line("Moon Grenade: last crater at " .. last_crater)
      end
    end)
  end,
}
