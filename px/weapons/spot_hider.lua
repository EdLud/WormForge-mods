-- Spot Hider: PX's zone launcher's third weapon, the one that hides a spot.
-- This is the entry point the component's install runs; the port itself is
-- lib/px_spot_hider.lua, which needs `wa` and so is loaded here rather than at
-- load (REPORT.md 11.11).

local spot_hider = require("lib/px_spot_hider")

return {
  defaults = {
    ammo = { round_start = -1 },
    delay = 0,
  },
  install = function(ctx)
    spot_hider.install(ctx)
  end,
}
