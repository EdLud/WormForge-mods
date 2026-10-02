-- A second weapon, outside the scheme's preset: the Profile tab adds it, and
-- it can swap places with Big Bazooka. It fires as a mortar wherever it sits.
return {
  defaults = {
    ammo = { round_start = 3 },
  },
  install = function(ctx)
    wa.log(("Big Mortar on %s at %s %d"):format(ctx.stock_slot, ctx.position.row, ctx.position.column))
    wa.weapons.replace({ weapon = ctx.stock_slot, copy_from = "mortar", name = "Big Mortar", params = { damage = 70 } })
  end,
}
