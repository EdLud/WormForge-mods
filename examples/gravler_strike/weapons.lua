-- PX's script replaces these four stock mole digging sprites. WA still owns
-- the mole strike's movement, terrain cuts, sounds, damage and stop conditions.
wa.weapons.replace({
  weapon = "donkey",
  name = "Gravler Strike",
  copy_from = "mole_squadron",
  panel_icon = "mole_squadron",
  stock_sprite_overrides = {
    [245] = "sprites/gravlerdive.png",
    [246] = "sprites/gravlerdiga.png",
    [247] = "sprites/gravlerdigb.png",
    [248] = "sprites/gravlerdigc.png",
  },
  is_weapon = true,
})
