-- The utilities feature: match settings the lobby scheme doesn't have, and
-- some players' favourite packs as switches. Every setting is an option of
-- this one component, read once at install.

-- The packs, by option: each module installs its hooks when loaded, so only
-- a switched-on one is loaded.
local PACKS = {
  { "ex_turn_side", "features/ex_turn_side" },
  { "agility", "features/agility" },
  { "live_hp", "features/live_hp" },
  { "collect_viewer", "features/collect_viewer" },
}

return function(ctx)
  local gravity_pct = ctx.option("gravity_pct")
  local wind = ctx.option("wind")
  local heal = ctx.option("heal_per_turn")

  -- The scheme's gravity, read at the first turn: scaling it again each turn
  -- would compound.
  local scheme_gravity
  -- WA sends a turn's start before it rolls that turn's wind (0x55C0CB, then
  -- 0x55C16C), so wind set at turn_start would be rolled over. It is set at
  -- the next frame instead, after WA's roll.
  local wind_due = false

  wa.on.turn_start(function(ev)
    if gravity_pct ~= 100 then
      scheme_gravity = scheme_gravity or wa.world.gravity()
      wa.world.set_gravity(scheme_gravity * gravity_pct / 100)
    end
    if heal > 0 then
      ev.worm:heal(heal)
    end
    wind_due = wind ~= "scheme"
  end)

  if wind ~= "scheme" then
    wa.on.worm_message(function()
      if wind_due then
        wind_due = false
        wa.world.set_wind(wind == "none" and 0 or wa.world.wind() / 2)
      end
    end, { msgs = { wa.msg.FRAME_FINISH } })
  end

  local on = {}
  for _, pack in ipairs(PACKS) do
    if ctx.option(pack[1]) then
      require(pack[2])
      on[#on + 1] = pack[1]
    end
  end

  wa.log(("gravity %d%%, wind %s, heal %d, packs %s"):format(
    gravity_pct, wind, heal, #on > 0 and table.concat(on, " ") or "none"))
end
