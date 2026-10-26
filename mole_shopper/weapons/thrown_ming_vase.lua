-- Thrown Ming Vase: source settings and weapon-scoped art.
local holds = require("wf-lib/holds")
local ART = "sprites/thrown_ming_vase/"

return {
  install = function()
    wa.weapons.replace{
      copy_from = "stock.ming_vase", name = "Thrown Ming Vase", panel_icon = ART .. "icon.png",
      sprite = ART .. "hold.png",
      params = {sprite_columns = 1},
      worm_sprites = holds.PX_POSTURE,
      hold = {sheet = ART .. "hold.png", frames = 1, thrown = true,
        hand = holds.PX_HANDS[1], hand_type = 1, hand_scale = 1.2,
        hand_radius = -11, hand_rotation = 0, hand_radial_rotation = 0,
        weap_radial_rotation = 0, weap_rotation = 0.5, weap_radius = -11.2},
      fires = {
        launch_power_pct = "charged",
        method = 3,
        subtype = 2,
        type = 1,
      },
      handling = {
        remember_selection = false,
        retreat = 3000,
      },
      missile = {
        animation = 5,
        countdown = 0,
        fuse = 10000,
        gravity_pct = 120,
        impact_particles = false,
        bounce = {
          bounciness = 50,
          contact_sides = 9,
          max_bounces = 100,
          sound = 0,
          terrain_keep_speed_pct = 50,
          hits = {
            water = true,
            worms_frozen = true,
          },
        },
        ends_on_contact = {
          crates = true,
          donor_cards = true,
          land = true,
          objects = true,
          water = true,
          worms = true,
        },
        explosion = {
          bias = 40,
          power = 65,
        },
        trail = {
          speed = 0,
          sprite = 0,
        },
      },
      clusters = {
        count = 4,
        bit = {
          flight_sound = 64,
          fuse = 10000,
          impact_particles = false,
          bounce = {
            hits = {
              water = true,
              worms_frozen = true,
            },
          },
          ends_on_contact = {
            crates = true,
            donor_cards = true,
            land = true,
            objects = true,
            water = true,
            worms = true,
            worms_frozen = true,
          },
          explosion = {
            bias = 40,
            power = 55,
          },
          trail = {
            power = 25,
            speed = 200,
            sprite = 250,
          },
        },
      },
    }
  end,
}
