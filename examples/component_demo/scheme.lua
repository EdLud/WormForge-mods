-- A scheme component: overrides for the weapons its preset places. Only the
-- fields it sets change; the rest stay the weapon's. A scheme may also return
-- install = function(ctx) ... end with round rules, if its mod.toml entry
-- declares changes_rules = true (the loader then says so).
return {
  -- Chance per turn of each crate kind, in %; the rest is no crate.
  crates = { weapon = 40, health = 10, utility = 20 },
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
}
