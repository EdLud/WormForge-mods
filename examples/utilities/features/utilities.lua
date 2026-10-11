-- The utilities feature: match settings the lobby scheme doesn't have. Every
-- setting is an option of this one component, read once at install.
return function(ctx)
  local gravity_pct = ctx.option("gravity_pct")
  local wind = ctx.option("wind")
  local heal = ctx.option("heal_per_turn")
  local infinite = {}
  for _, weapon in ipairs({ "jet_pack", "parachute", "ninja_rope" }) do
    if ctx.option("infinite_" .. weapon) then
      infinite[#infinite + 1] = weapon
    end
  end

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
    for _, weapon in ipairs(infinite) do
      ev.worm:ammo(weapon, { set = -1 })
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

  wa.log(("gravity %d%%, wind %s, heal %d, infinite %s"):format(
    gravity_pct, wind, heal, #infinite > 0 and table.concat(infinite, " ") or "none"))
end
