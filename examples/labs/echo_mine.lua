-- MineEntity stays the mine. Boom is a CLUSTER actor (fan, trail, impact).
return {
  install = function()
    wa.weapons.replace({
      name = "Echo Mine",
      copy_from = "stock.mine",
      panel_icon = "mine",
      sprite = "crshairr",
      mine = {
        proximity = 25,
        trigger = 10,
      },
      on_proximity = {
        spawn = {
          sprite = false,
          explode = { damage = 0, id = 25, now = true },
          damage_worms = false,
          damage_terrain = true,
        },
        on = function(ev)
          wa.log("echo proximity")
        end,
      },
      on_explode = {
        spawn = {
          kind = "cluster",
          sprite = "banana",
          trail = "smklt25",
          count = 5,
          spread = 45,
          power = 0,
          impact = true,
          bounce = false,
          homing = false,
          gravity = true,
          collide = true,
          persist = false,
          explode = { damage = 30, id = 100 },
        },
        on = function(ev)
          wa.log("echo explode")
        end,
      },
    })
  end,
}
