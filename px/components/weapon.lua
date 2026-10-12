-- A Highlander weapon as a component: every one of the bundle's weapon
-- components runs this file, and ctx.stock_slot says which weapon it is.
-- Highlander's weapons keep their stock slots' ammo, delay and crate odds
-- unless the scheme sets them; under the Highlander scheme its rules deal
-- the ammo.
return {
  install = function(ctx)
    require("components/loader").install(ctx)
  end,
}
