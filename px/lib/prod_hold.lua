-- WA's Prod hold for a turret on the Mine's record: the arm reaches out, pokes and pulls back.

local ART = "sprites/pyro_turrets/"

return {
  worm_sprites = {
    weaponlnk = ART .. "prod_out.png", weaponlnku = ART .. "prod_outu.png",
    weaponlnkd = ART .. "prod_outd.png",
    wthrow = ART .. "prod_back.png", wthrowu = ART .. "prod_backu.png",
    wthrowd = ART .. "prod_backd.png",
  },
  params = { worm_sprites_animate = true },
}
