-- The utilities feature: match settings the lobby scheme doesn't have, and
-- some players' favourite packs as switches. Every setting is an option of
-- this one component, read once at install.

-- The packs, by option: each module installs its hooks when loaded, so only
-- a switched-on one is loaded. A `choice` pack is a function of its choice,
-- "off" not loading it.
local PACKS = {
  { "ex_turn_side", "features/ex_turn_side" },
  { "agility", "features/agility" },
  { "parkour", "features/parkour" },
  { "live_hp", "features/live_hp" },
  { "instant_death", "features/instant_death", choice = true },
  { "collect_viewer", "features/collect_viewer" },
}

return function(ctx)
  local heal = ctx.option("heal_per_turn")
  if heal > 0 then
    -- The turn's first worm only: a worm switch within the turn (Tab,
    -- Select Worm) runs turn_start again, with no turn_end before it.
    local healed = false
    wa.on.turn_start(function(ev)
      if healed then return end
      healed = true
      ev.worm:heal(heal)
    end)
    wa.on.turn_end(function() healed = false end)
  end

  local on = {}
  for _, pack in ipairs(PACKS) do
    local value = ctx.option(pack[1])
    if value and value ~= "off" then
      local pack_module = require(pack[2])
      if pack.choice then pack_module(value) end
      on[#on + 1] = pack[1]
    end
  end
  
  if ctx.option("damage_numbers") then
    require("features/damage_numbers")({
      side = ctx.option("damage_numbers_side"),
    })
    on[#on + 1] = "damage_numbers"
  end

  wa.log(("heal %d, packs %s"):format(
    heal, #on > 0 and table.concat(on, " ") or "none"))
end
