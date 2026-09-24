-- PX's script replaces these four stock mole digging sprites. WA still owns
-- the mole strike's movement, terrain cuts, sounds, damage and stop conditions.
wa.weapons.replace({
  weapon = "donkey",
  name = "Gravler Strike",
  copy_from = "mole_squadron",
  panel_icon = "mole_squadron",
  stock_sprite_overrides = {
    moledive = "sprites/gravlerdive.png",
    moledig1 = "sprites/gravlerdiga.png",
    moledig2 = "sprites/gravlerdigb.png",
    moledig3 = "sprites/gravlerdigc.png",
  },
  is_weapon = true,
})
