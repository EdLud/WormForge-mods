-- Marked For Death: click a worm to mark it; the mark's damage multiplier is
-- the `dmg_percent` option (150% by default). PX refunds the shot when the
-- click finds nobody.
local curse = require("lib/curse")

local M = {}

function M.install(ctx)
  if not curse.placed(ctx) then
    wa.log("Marked For Death: in no panel slot; nothing registered")
    return
  end
  curse.install()
  local mult = (ctx.option("dmg_percent") or 150) / 100
  wa.weapons.replace({
    wep = "weps/marked_for_death.wep",
    name = "Marked For Death",
    panel_icon = "sprites/curse/whitemark_icon.png",
    on_click = function(ev)
      local w = curse.at(ev.worm, ev.x, ev.y)
      if w then
        curse.mark(w, mult)
      else
        -- finish_click_shot takes the ammo after this returns; add it back.
        ev.worm:ammo(ctx.id, 1)
        curse.nothing_found(ev.worm)
      end
    end,
  })
end

return M
