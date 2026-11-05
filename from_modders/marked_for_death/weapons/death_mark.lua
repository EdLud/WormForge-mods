-- Death Mark: marks the worm in front; the mark's damage multiplier is the
-- `dmg_percent` option (150% by default). PX's record does not end the turn,
-- so the shooter still has their move.
local curse = require("lib/curse")

local M = {}

function M.install(ctx)
  if not curse.placed(ctx) then
    wa.log("Death Mark: in no panel slot; nothing registered")
    return
  end
  curse.install()
  local mult = (ctx.option("dmg_percent") or 150) / 100
  wa.weapons.replace({
    wep = "weps/death_mark.wep",
    name = "Death Mark",
    panel_icon = "sprites/curse/whiteprod_icon.png",
    on_fire = function(ev)
      local w = curse.front(ev.worm)
      if w then curse.mark(w, mult) end
    end,
  })
end

return M
