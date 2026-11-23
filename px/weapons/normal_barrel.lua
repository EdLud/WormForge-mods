-- Normal Barrel: launches an ordinary oil drum.

local weapon = {}
local ID = "px.normal_barrel"
local ART = "sprites/barrel_launcher/"

local function launch(fire)
  local worm = fire.worm
  if wa.world.collides({ x = fire.x, y = fire.y, radius = 9 }) then
    wa.sound.play(worm, 120)
    worm:ammo(ID, 1)
    require("lib/weapon_hint").notice(worm, "No space to launch!")
    return
  end
  local drum = wa.oil.spawn({ x = fire.x, y = fire.y, snap = false })
  if drum then drum.vx, drum.vy = fire.vx, fire.vy end
end

weapon.definition = {
  wep = "weps/barrel_launcher.wep",
  name = "Normal Barrel",
  panel_icon = "sprites/normal_barrel/normal_barrel_ico.png",
  worm_sprites = {
    weaponlnk = ART .. "aim.png", weaponlnku = ART .. "aimu.png", weaponlnkd = ART .. "aimd.png",
    wthrow = ART .. "draw.png", wthrowu = ART .. "drawu.png", wthrowd = ART .. "drawd.png",
  },
  on_fire = launch,
}

return weapon
