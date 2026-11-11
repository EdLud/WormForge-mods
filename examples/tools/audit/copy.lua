-- Audit copy: one stock weapon, copied unchanged; its id names the weapon.

return {
  install = function(ctx)
    wa.weapons.replace({ copy_from = "stock." .. ctx.id:gsub("^tools%.copy_", "") })
  end,
}
