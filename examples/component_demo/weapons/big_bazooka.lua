-- A weapon component: its data, and what it does once placed. `wa` is only
-- available inside install; this file itself just returns the table.
return {
  defaults = {
    ammo = { round_start = -1 },
    delay = 0,
  },
  install = function(ctx)
    -- ctx.data is these defaults with the scheme's overrides laid over them.
    wa.log(("Big Bazooka on %s at %s %d: round_start %d, delay %d"):format(
      ctx.stock_slot, ctx.position.row, ctx.position.column, ctx.data.ammo.round_start, ctx.data.delay))
    wa.weapons.replace({ weapon = ctx.stock_slot, copy_from = "bazooka", name = "Big Bazooka", params = { damage = 80 } })
  end,
}
