-- Bible Launcher: launches a bible that bounces, exploding at each bounce.

local weapon = {}

weapon.record = {
  missile = {
    animation = 5,
    bounce = {
      bounciness = 65,
      contact_sides = 10,
      explosion = {
        power = 35,
        push_pct = 50,
      },
      hits = {
        land = true,
        water = true,
        worms = true,
        worms_frozen = true,
      },
      max_bounces = 4,
      sound = 105,
      terrain_keep_speed_pct = 40,
    },
    ends_on_contact = {},
    explosion = {
      power = 40,
      push_pct = 50,
    },
    impact_particles = false,
    trail = {
      power = 35,
      speed = 50,
      sprite = 80,
    },
    wind_pct = 0,
  },
}

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.bazooka",
    name = "Bible Launcher",
    panel_icon = "sprites/bible_launcher/bible_ico.png",
    sprite = "sprites/bible_launcher/bible.png",
  })
end

return weapon
