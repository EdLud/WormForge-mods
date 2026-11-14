-- Scatter Bazooka: a bazooka that fires three smaller rockets in a fan.

local SPREAD = math.rad(10) -- between two rockets

return {
  defaults = {
    ammo = { round_start = 2 },
    delay = 2,
  },

  install = function(ctx)
    -- ctx.data: the defaults above, with the settings of the profile over them.
    local p = ctx.position
    wa.log(("on %s, column %d: ammo %d, delay %d"):format(
      p.row, p.column, ctx.data.ammo.round_start, ctx.data.delay))

    wa.weapons.replace{
      copy_from = "stock.bazooka",
      missile = { explosion = { power = 30 } },

      -- Runs in place of the rocket the Bazooka fires.
      on_fire = function(fire)
        for i = -1, 1 do
          local c, s = wa.math.cos(i * SPREAD), wa.math.sin(i * SPREAD)
          wa.weapons.launch{
            weapon = ctx.id, -- this weapon: power 30, and its callbacks
            owner = fire.worm,
            x = fire.x,
            y = fire.y,
            vx = fire.vx * c - fire.vy * s,
            vy = fire.vx * s + fire.vy * c,
          }
        end
      end,
    }
  end,
}
