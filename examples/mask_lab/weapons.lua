-- Click places the fox PNG. First-frame opaque pixels become the walk/hit mask
-- (black bg punched to alpha). Stress-tests fine fur edges vs auto-mask.

wa.weapons.replace({
  weapon = "prod",
  name = "Mask Fox",
  is_weapon = true,

  on_select = {
    cursor = true,
  },

  on_click = {
    spawn = {
      sprite = "sprites/fox.png",
      from = "cursor",
      origin = "bottom",
      gravity = true,
      collide_terrain = true,
      persist = true,
      drown = true,
      mask = true,
      mask_worms = true,
      mask_land = true,
      mask_weapons = true,
      mask_actors = true,
    },
  },
})
