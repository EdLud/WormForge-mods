-- Moon Grenade: WA's Grenade with about a third of the gravity and a small
-- burst, which digs three craters in the ground below it.

return {
  -- The weapon's data. The profile's settings for it (the loader's
  -- Manage Weapon Panel) are laid over these, field by field.
  defaults = {
    ammo = { round_start = 3 },
  },

  install = function()
    local last_burst -- set by the simulation, shown by the HUD

    wa.weapons.replace{
      copy_from = "stock.grenade",
      missile = {
        gravity_pct = 35,
        explosion = { power = 20 },
      },

      -- Simulation: runs on every player's machine at the same moment,
      -- so it may change the game and roll WA's dice.
      on_explode = function(ev)
        -- One crater down-right, one straight down, one down-left. The dice
        -- pick each one's angle within its part (0 degrees is right, 90 is
        -- straight down), its distance and its size.
        for i = 0, 2 do
          local angle = math.rad(20 + 60 * i + wa.random(0, 20))
          local distance = wa.random(60, 85)
          wa.land.cut{
            x = ev.x + distance * wa.math.cos(angle),
            y = ev.y + distance * wa.math.sin(angle),
            shape = "circle",
            radius = wa.random(12, 18),
          }
        end
        last_burst = ("%d, %d"):format(math.floor(ev.x), math.floor(ev.y))
        wa.log("craters below " .. last_burst)
      end,
    }

    -- Drawing: runs on each machine when it draws a frame, so it only reads.
    wa.on.hud(function()
      if last_burst then
        wa.hud.line("Moon Grenade: craters below " .. last_burst)
      end
    end)
  end,
}
