-- Project X's oil drums, the px.oil_drums add-on: every oil drum on the map
-- is one of PX's kinds (lib/oil_drums). It installs before the weapons
-- (before_weapons) so the Electric Grenade's arc, which the electric drum
-- fires, is set up whether or not the grenade is placed.

return {
  install = function(ctx)
    local loader = require("components/loader")
    loader.also("weapons/electric_grenade")
    -- PX's icy drum takes a Swim Suit off: only a placed one can be on.
    loader.load(loader.place(ctx))
    local drums = require("lib/oil_drums")
    drums.load_assets()
    -- The nuke drum fires the Nuke Rocket's rockets, which only a placed
    -- Nuke Rocket launches.
    drums.install({ deal = true, nuke = ctx.weapons["px.nuke_rocket"] ~= nil })
  end,
}
