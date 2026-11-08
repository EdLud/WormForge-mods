-- Homing Curse: curses the worm in front, so loose mines, missiles, oil drums
-- and arrows home at it for two turns, and magnetic actors are pulled at it.
local curse = require("lib/curse")

local M = {}

function M.install(ctx)
  if not curse.placed(ctx) then
    wa.log("Homing Curse: in no panel slot; nothing registered")
    return
  end
  curse.install()
  local cap = ctx.option("max_homing") or 3
  wa.weapons.replace({
    wep = "weps/homing_curse.wep",
    name = "Homing Curse",
    panel_icon = "sprites/curse/redprod_icon.png",
    on_fire = function(ev)
      local w = curse.front(ev.worm)
      if w then curse.curse(w, cap) end
    end,
  })
end

return M
