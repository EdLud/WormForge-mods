-- Mole Herd Launcher: launches a mole that splits into three digging moles.

local weapon = {}

weapon.record = {
  fires = {
    launch_power_pct = 35,
    method = 3,
    subtype = 3,
    type = 1,
  },
  handling = {
    retreat = 3000,
  },
  missile = {
    explosion = {
      push_pct = 0,
    },
    trail = {
      power = 50,
      sprite = 80,
    },
  },
  clusters = {
    count = 3,
    launch_power_pct = 50,
    spread = 50,
    bit = {
      explosion = {
        power = 40,
      },
      fuse = 10000,
      random_motion = 60,
    },
  },
}

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.mole_bomb",
    name = "Mole Herd Launcher",
    panel_icon = "sprites/launchers/mhl_ico.png",
  })
end

return weapon
