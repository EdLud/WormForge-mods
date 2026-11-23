-- Hotchkiss: a machine gun firing long bursts of light bullets.

local weapon = {}

weapon.record = {
  gun = {
    bullets = 35,
    burst_size = 4,
    burst_spread_deg = 9,
    damage = 4,
    explosion = {
      bias = 10,
      push_pct = 110,
      variation = 5,
    },
    impact_effect = 10,
    shot_interval_ms = 50,
    spread_deg = 23,
  },
}

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.handgun",
    name = "Hotchkiss",
    panel_icon = "sprites/hotchkiss/ico_hotchkiss.png",
    worm_sprites = {
      weaponlnk = "sprites/hotchkiss/aim.png",
      weaponlnku = "sprites/hotchkiss/aimu.png",
      weaponlnkd = "sprites/hotchkiss/aimd.png",
      wthrow = "sprites/hotchkiss/draw.png",
      wthrowu = "sprites/hotchkiss/drawu.png",
      wthrowd = "sprites/hotchkiss/drawd.png",
      weaponfire = "sprites/hotchkiss/fire.png",
      weaponfireu = "sprites/hotchkiss/fireu.png",
      weaponfired = "sprites/hotchkiss/fired.png",
    },
  })
end

return weapon
