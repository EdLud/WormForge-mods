-- Wish Of Death: click a worm to curse it.

local curse = require("lib/curse")

local M = {}

function M.install(ctx)
  if not curse.placed(ctx) then
    wa.log("Wish Of Death: in no panel slot; nothing registered")
    return
  end
  curse.install()
  local cap = ctx.option("max_homing") or 3
  wa.weapons.replace({
    wep = "weps/wish_of_death.wep",
    name = "Wish Of Death",
    panel_icon = "sprites/curse/markicon.png",
    on_click = function(ev)
      local w = curse.at(ev.worm, ev.x, ev.y)
      if w then
        curse.curse(w, cap)
      else
        ev.worm:ammo(ctx.id, 1)
        curse.nothing_found(ev.worm)
      end
    end,
  })
end

return M
