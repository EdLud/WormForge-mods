-- The Highlander scheme: its preset places every Highlander weapon, and its
-- rules deal them (scheme/pools, scheme/state, scheme/rules) wherever the
-- profile put them. It installs before the weapons, so its hooks run first.
--
-- What it gives outside the deal is weapon data, which the loader shows and
-- a player may change: PX's GiveWeapons refills the Hot Air Balloons to 3 and
-- the Wind Changer to 1 each turn, and each team gets one Weapon Crate a
-- round.
return {
  weapons = {
    ["hl.hot_air_balloon"] = { ammo = { round_start = 3, turn_start = { amount = 3, mode = "replace" } } },
    ["hl.wind_changer"] = { ammo = { round_start = 1, turn_start = { amount = 1, mode = "replace" } } },
    ["hl.weapon_crate"] = { ammo = { round_start = 1 } },
  },
  install = function(ctx)
    require("components/loader").place(ctx)
    require("scheme/pools")
    require("scheme/state")
    require("scheme/rules")
  end,
}
