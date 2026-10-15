-- A plain copy of one of WA's weapons, for the audit's `copies` run: its id
-- names the weapon (tools.copy_<name>), and nothing of it is changed.
return {
  install = function(ctx)
    wa.weapons.replace({ copy_from = "stock." .. ctx.id:gsub("^tools%.copy_", "") })
  end,
}
