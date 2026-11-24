-- Frag Grenade: a heavy grenade that explodes on impact.

local holds = require("wf-lib/holds")
local weapon = {}

local ART = "sprites/frag_grenade/"

weapon.record = {
  missile = {
    sprite = 0, -- WA draws no grenade; the art spec draws it
    alarm_worms = false,
    animation = 4,
    bounce = {
      bounciness = 80,
      contact_sides = 0,
      hits = {
        crates = true,
        donor_cards = true,
        mines = true,
        missiles = true,
        water = true,
        worms_frozen = true,
      },
      max_bounces = 10,
      sound = 110,
      terrain_keep_speed_pct = 80,
    },
    countdown = 0,
    ends_on_contact = {
      arrows = true,
      land = true,
      objects = true,
      water = true,
      worms = true,
    },
    explosion = {
      power = 43,
      push_pct = 125,
    },
    fuse = 10000,
    gravity_pct = 148,
    impact_particles = false,
    trail = {
      power = 10,
      speed = 250,
      sprite = ART .. "trail.png",
    },
  },
}

weapon.missile_sprite = { sheet = ART .. "frag.png", frames = 1, spin = true, hide = true }

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.grenade",
    name = "Frag Grenade",
    panel_icon = ART .. "ico_frag.png",
    worm_sprites = holds.PX_POSTURE,
    sprites = { ART .. "frag.png" },
    hold = {
      thrown = true,
      -- The Fire Cluster Bomb's hold, at the chest: PX's values (hand_radius
      -- -9.5, weap_radius -11.2, hand_scale 1.2) holds it up at the face.
      sheet = ART .. "frag.png", hand_type = 1, hand_radius = 16,
      weap_rotation = 0.5, weap_radius = 9,
      hand = holds.PX_HANDS[1],
    },
  })
end

return weapon
