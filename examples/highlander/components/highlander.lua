-- The Highlander scheme: its preset places every Highlander weapon, and its
-- rules deal them (scheme/pools, scheme/state, scheme/rules). It installs
-- before the weapons, so its hooks run first.
return {
  install = function()
    require("scheme/pools")
    require("scheme/state")
    require("scheme/rules")
  end,
}
