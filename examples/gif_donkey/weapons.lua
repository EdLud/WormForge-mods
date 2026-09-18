-- GUI / checkbox path. Native runs these statuses each FRAME_FINISH.
-- A later editor generates this table from dropdowns. No Lua brain.

wa.weapons.replace({
  weapon = "grenade",
  name = "Growth Hormones",
  is_weapon = true,

  on_select = {
    cursor = true,
  },

  on_click = {
    spawn = {
      sprite = "sprites/200w.gif",
      loop = true,
      from = "sky",
      origin = "bottom",
      gravity = true,
      collide_terrain = true,
      damage_terrain = true,
      collide_worms = true,
      damage_worms = true,
      persist = true,
      drown = true,
      explode = {
        damage = 50,
        id = 100,
        below = true,
      },
    },
  },
})
