-- A scheme component: overrides for the weapons its preset places, and its
-- round rules. Only the fields it sets change; the rest stay the weapon's.
return {
  weapons = {
    ["demo.big_bazooka"] = { delay = 1 },
    -- Stock weapons have no defaults: unset fields keep the lobby scheme's.
    ["stock.grenade"] = { ammo = { round_start = -1 } },
    ["stock.shotgun"] = { ammo = { round_start = -1 } },
    ["stock.ninja_rope"] = { ammo = { round_start = 5 } },
    ["stock.teleport"] = { ammo = { round_start = 2 }, crate = { chance_pct = 40 } },
    ["stock.skip_go"] = { ammo = { round_start = -1 } },
    ["stock.surrender"] = { ammo = { round_start = -1 } },
  },
  install = function(ctx)
    local ids = {}
    for id in pairs(ctx.weapons) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      wa.log(("scheme places %s on %s"):format(id, ctx.weapons[id].stock_slot))
    end
  end,
}
