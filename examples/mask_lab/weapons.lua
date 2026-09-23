-- Experimental mask lab (Prod).
-- Places an animated GIF whose walk/hit solid swaps each anim frame to match
-- the silhouette. Stand a worm on top to feel how cursed that is.
-- Static PNGs (sprites/fox.png) use a single baked mask — prefer that for real packs.

wa.weapons.replace({
  weapon = "prod",
  name = "Mask GIF (experimental)",
  is_weapon = true,

  on_select = {
    cursor = true,
  },

  on_click = {
    spawn = {
      sprite = "sprites/banner.gif",
      from = "cursor",
      origin = "bottom",
      gravity = true,
      loop = true,
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
