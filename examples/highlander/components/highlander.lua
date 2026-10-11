-- The Highlander scheme: its preset places every Highlander weapon, and its
-- rules deal them (scheme/pools, scheme/state, scheme/rules) wherever the
-- profile put them. It installs before the weapons, so its hooks run first.
return {
  install = function(ctx)
    require("components/loader").place(ctx)
    require("scheme/pools")
    require("scheme/state")
    require("scheme/rules")
  end,
}
