-- Ripple Grenade: WA's Grenade whose burst sends a ripple through the
-- world's picture. The ripple is presentation only, so the explosion (a
-- simulation callback) may start it: every machine draws its own, and
-- nothing in the game can read it back.

return {
  install = function()
    wa.weapons.replace{
      copy_from = "stock.grenade",

      on_explode = function(ev)
        -- Pixels, pixels per second and milliseconds. A falloff shorter
        -- than the wavelength leaves one ring; a longer one, a train.
        wa.view.ripple{
          x = ev.x,
          y = ev.y,
          amplitude = 8,
          wavelength = 40,
          speed = 320,
          duration_ms = 900,
          falloff = 60,
        }
      end,
    }
  end,
}
