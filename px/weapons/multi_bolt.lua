-- Multi-Bolt: a bolt that explodes on contact into six bouncing bolts.

local weapon = {}

local ART = "sprites/multi_bolt/"

weapon.record = {
  missile = {
    sprite = 0, -- WA draws no bolt; the art spec draws it
    bounce = {
      bounciness = 80,
      contact_sides = 0,
      hits = {
        water = true,
        worms_frozen = true,
      },
      max_bounces = 10,
      sound = 83,
      terrain_keep_speed_pct = 80,
    },
    burst = "clusters",
    ends_on_contact = {
      crates = true,
      donor_cards = true,
      land = true,
      mines = true,
      objects = true,
      water = true,
      worms = true,
    },
    explosion = {
      power = 15,
      push_pct = 220,
    },
    flight_sound = 8,
    fuse = 10000,
    gravity_pct = 130,
    impact_particles = false,
    trail = {
      power = 30,
      speed = 300,
      sprite = ART .. "trail.png",
    },
    wind_pct = 0,
  },
  clusters = {
    count = 6,
    launch_power_pct = 25,
    power_variation_pct = 460,
    spread = 100,
    bit = {
      action = "bounce",
      animation = 2,
      bounce = {
        bounciness = 10,
        contact_sides = 15,
        extra_reverse_chance_pct = 15,
        hits = {
          crates = true,
          donor_cards = true,
          land = true,
          missiles = true,
          water = true,
          worms_frozen = true,
        },
        max_bounces = 3,
        sound = 83,
        terrain_keep_speed_pct = 10,
      },
      ends_on_contact = {
        mines = true,
        objects = true,
        water = true,
        worms = true,
      },
      explosion = {
        bias = 8,
        power = 25,
        push_pct = 240,
      },
      flight_sound = 122,
      fuse = 10000,
      gravity_pct = 120,
      impact_particles = false,
      speed_pct = 98,
      sprite_count = 1,
      trail = {
        bubbles_per_second = 12.5,
        power = 25,
        speed = 235,
        sprite = ART .. "cluster_trail.png",
      },
    },
  },
}

weapon.missile_sprite = { sheet = ART .. "multib.png", animate = true, anim_speed = 1.40, frames = 12, hide = true }

function weapon.definition()
  local sdk = require("wf-lib/holds")
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.bazooka",
    name = "Multi-Bolt",
    panel_icon = ART .. "ico_multib.png",
    cluster_sprite = ART .. "multibc.png",
    worm_sprites = sdk.PX_POSTURE,
    sprites = { ART .. "spb_multib.png", ART .. "multib.png" },
    hold = {
      keep_while_firing = true,
      sheet = ART .. "spb_multib.png", draw_hand = false, hand_radius = 0.0,
      hand_rotation = 0.0, hand_radial_rotation = 0.0,
      weap_rotation = 1.0, weap_radial_rotation = 0.0, weap_radius = 3.5,
      animate = true, anim_speed = 1.35, frames = 12,
    },
  })
end

return weapon
