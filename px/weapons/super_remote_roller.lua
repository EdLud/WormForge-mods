-- Super Remote Roller: a thrown roller that splits into four rollers; Space sets them off.

local weapon = {}

local ART = "sprites/super_remote_roller/"

weapon.record = {
  fires = {
    launch_power_pct = 35,
    method = 3,
    subtype = 2,
    type = 1,
  },
  missile = {
    ends_on_contact = {
      water = true,
    },
    explosion = {
      bias = 10,
      power = 45,
      push_pct = 105,
    },
    flight_sound = 88,
    fuse = 10000,
    impact_particles = true,
    roam = {
      edge_jump = {
        angle_deg = 25,
        sound = 88,
        speed = 4.5,
      },
      flight_hits = {
        water = true,
      },
      hits = {
        crates = true,
        donor_cards = true,
        land = true,
        objects = true,
        water = true,
        worms_acting = true,
        worms_frozen = true,
        worms_jumping = true,
        worms_normal = true,
      },
      jump = {
        angle_deg = 0,
        sound = 88,
        speed = 0.0,
      },
      step_height = 20,
      terrain_offset = -6,
      walk_speed = 2.4,
    },
    trail = {
      power = 20,
      speed = 50,
      sprite = ART .. "trail.png",
    },
  },
  clusters = {
    count = 4,
    launch_power_pct = 55,
    power_variation_pct = 70,
    spread = 45,
    bit = {
      ends_on_contact = {
        water = true,
      },
      explosion = {
        bias = 25,
        power = 40,
        push_pct = 130,
      },
      flight_sound = 88,
      gravity_pct = 140,
      random_motion = 30,
      roam = {
        edge_jump = {
          angle_deg = 25,
          sound = 88,
          speed = 3.78,
        },
        flight_hits = {
          worms = true,
        },
        gas = {
          animal_sprite = 0,
          poison_power = 0,
          start_delay_ms = 0,
        },
        jump = {
          angle_deg = 0,
          sound = 88,
          speed = 0.0,
        },
        step_height = 20,
        walk_speed = 2.3,
      },
      trail = {
        power = 15,
        speed = 50,
        sprite = ART .. "cluster_trail.png",
      },
    },
  },
}

function weapon.definition()
  local sdk = require("wf-lib/holds")
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.skunk",
    name = "Super Remote Roller",
    panel_icon = ART .. "ico_sremoter.png",
    sprite = ART .. "sremoter.png",
    cluster_sprite = ART .. "remoter.png",
    worm_sprites = sdk.PX_POSTURE,
    hold = {
      thrown = true,
      -- At the chest, as the Fire Cluster Bomb's hold, a little further out for
      -- the bigger roller: PX's values (hand_radius -16, weap_radius -11.5,
      -- hand_scale 1.15) holds it up at the face.
      sheet = ART .. "sremoter.png", frames = 12, hand_type = 1, hand_radius = 18,
      weap_rotation = 0.5, weap_radius = 11,
      animate = true, anim_speed = 1.2,
      hand = sdk.PX_HANDS[1],
    },
  })
end

return weapon
