-- A scheme component: overrides for the weapons its preset places, and its
-- round rules. Only the fields it sets change; the rest stay the weapon's.
return {
  weapons = {
    ["demo.big_bazooka"] = { delay = 1 },
  },
  install = function(ctx)
    for id, w in pairs(ctx.weapons) do
      wa.log(("scheme places %s on %s"):format(id, w.stock_slot))
    end
  end,
}
