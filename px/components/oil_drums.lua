-- Project X's oil drums, the px.oil_drums add-on: every oil drum on the map
-- is one of PX's kinds (lib/oil_drums). It installs before the weapons
-- (before_weapons) so the Tazer's arc (lib/electrical), which the electric
-- drum fires, is set up whether or not an electric weapon is placed.

return {
  install = function(ctx)
    local loader = require("components/loader")
    loader.also("lib/electrical")
    -- The nuke drum fires the Nuke Rocket's rockets: the manifest launches
    -- it, so it has a slot even off the panel, and its module runs here.
    loader.also("weapons/nuke_rocket")
    -- PX's icy drum takes a Swim Suit off: only a placed one can be on.
    loader.load(loader.place(ctx))
    local drums = require("lib/oil_drums")
    drums.load_assets()
    drums.install({ deal = true })
  end,
}
