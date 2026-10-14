-- PX's script replaces these four stock mole digging sprites. WA still owns
-- the mole strike's movement, terrain cuts, sounds, damage and stop conditions.
-- PX's Gravler has no underwater art, so a gravler that dives into water sinks
-- as its dive frame under PX's sinking tint (no `mole` key needed here).
return {
  install = function()
    wa.weapons.replace({
      name = "Gravler Strike",
      copy_from = "stock.mole_squadron",
      panel_icon = "mole_squadron",
      mole_dig_rotation = {
        moledive = "sprites/gravlerdive.png",
        moledig1 = "sprites/gravlerdiga.png",
        moledig2 = "sprites/gravlerdigb.png",
        moledig3 = "sprites/gravlerdigc.png",
      },
      is_weapon = true,
    })
  end,
}
