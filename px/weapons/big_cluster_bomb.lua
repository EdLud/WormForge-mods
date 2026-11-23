-- Big Cluster Bomb: the stock cluster bomb, with a stronger blast and stronger clusters.

local weapon = {}

weapon.record = {
  missile = {
    explosion = {
      power = 35,
    },
  },
  clusters = {
    bit = {
      explosion = {
        power = 35,
      },
    },
  },
}

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.cluster_bomb",
    name = "Big Cluster Bomb",
    panel_icon = "cluster",
  })
end

return weapon
