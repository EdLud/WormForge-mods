-- Occupies the stock bazooka slot. This version cannot add a 72nd weapon.
wa.weapons.register({
  id = "example.ice_bazooka",
  based_on = "bazooka",
  name = "Ice Bazooka",
  sprites = {
    icon = "sprites/icon.png",
    projectile = "sprites/proj.png",
  },
  params = {
    damage = 45,
    bounce_pct = 100,
  },
})
