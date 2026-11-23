-- Bomb-omb: a walking bomb that explodes on bumping into a worm, scattering sparks.

local weapon = {}

local ART = "sprites/bomb_omb/"

weapon.record = {
  fires = {
    subtype = 1,
  },
  missile = {
    burst = "clusters",
    countdown = 0,
    ends_on_contact = {
      arrows = true,
      water = true,
      worms_acting = true,
      worms_normal = true,
    },
    explode_on_space = false,
    explosion = {
      bias = 20,
      power = 40,
      push_pct = 140,
    },
    flight_sound = 65562,
    fuse = 10000,
    roam = {
      edge_jump = {
        angle_deg = 40,
        sound = 99,
        speed = 3.6,
      },
      flight_hits = {
        arrows = true,
        crates = true,
        donor_cards = true,
        land = true,
        objects = true,
        water = true,
        worms = true,
        worms_frozen = true,
      },
      jump = {
        angle_deg = -1,
      },
      step_height = 8,
      terrain_offset = -6,
      walk_speed = 2.8,
    },
    trail = {
      power = 10,
      speed = 40,
      sprite = ART .. "trail.png",
    },
  },
  -- Sparks: they bounce about and burst without a blast.
  clusters = {
    count = 5,
    launch_power_pct = 50,
    power_variation_pct = 85,
    spread = 100,
    bit = {
      action = "bounce",
      animation = 1,
      bounce = {
        bounciness = 60,
        hits = {
          crates = true,
          donor_cards = true,
          land = true,
          objects = true,
          water = true,
          worms_frozen = true,
        },
        max_bounces = 100,
        sound = 108,
        terrain_keep_speed_pct = 70,
      },
      ends_on_contact = {
        water = true,
      },
      explosion_sound = {
        before = 1,
        enabled = true,
        sound = 115,
      },
      fuse = 1500,
      gravity_pct = 123,
      impact_particles = false,
      random_motion = 15,
      speed_pct = 98,
      sprite_count = 1,
      trail = {
        bubbles_per_second = 12.5,
        power = 10,
        speed = 150,
        sprite = ART .. "cluster_trail.png",
      },
    },
  },
}

function weapon.definition()
  local sdk = require("wf-lib/holds")
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.sheep",
    name = "Bomb-omb",
    panel_icon = ART .. "ico_bombb.png",
    sprite = ART .. "bombb.png",
    cluster_sprite = ART .. "bombbc.png",
    worm_sprites = {
      weaponlnk = sdk.PX_LEVEL.weaponlnk, weaponlnku = sdk.PX_LEVEL.weaponlnku,
      weaponlnkd = sdk.PX_LEVEL.weaponlnkd,
      wthrow = sdk.PX_POSTURE.wthrow, wthrowu = sdk.PX_POSTURE.wthrowu, wthrowd = sdk.PX_POSTURE.wthrowd,
    },
    hold = {
      thrown = true,
      sheet = ART .. "bombb.png", frames = 15, hand_type = 1, hand_scale = 1.2, hand_radius = -11.0,
      weap_rotation = 0.5, weap_radius = -11.0,
      animate = true, anim_speed = 0.93,
      static = { weap = 0.0, hand = 0.4 }, -- ang_if_static, hand_ang_if_static
      hand = sdk.PX_HANDS[1],
    },
  })
end

return weapon
