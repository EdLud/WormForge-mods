-- PX's Gravler Strike uses mole-strike weapon data, while its script only
-- replaces the four stock mole digging sprites (245..248). Keep the stock
-- mole strike's movement, terrain cuts, sounds, damage and stop conditions.
wa.weapons.replace({
  weapon = "donkey",
  name = "Gravler Strike",
  copy_from = "mole_squadron",
  panel_icon = "mole_squadron",
  is_weapon = true,
})
