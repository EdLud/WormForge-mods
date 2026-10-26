-- A thrown, three-second bomb with 33 gravity-free, penetrating children.
local holds = require("wf-lib/holds")
local ART = "sprites/i_bomb/"

return {
  install = function()
    wa.weapons.replace{
      copy_from = "stock.grenade", name = "i-bomb", panel_icon = ART .. "icon.png",
      sprite = ART .. "body",
      cluster = {sprite = ART .. "fragment", sprite_columns = 1},
      worm_sprites = holds.PX_POSTURE,
      params = {sprite_columns = 1},
      hold = {sheet = ART .. "hold.png", frames = 1, thrown = true,
        hand = holds.PX_HANDS[1], hand_type = 1, hand_scale = 1,
        hand_radius = -9, hand_rotation = 0, hand_radial_rotation = 0,
        weap_radial_rotation = 0, weap_rotation = 0.5, weap_radius = -11},
      handling = {
        remember_selection = false,
      },
      missile = {
        burst = "clusters",
        countdown = 3000,
        fuse = 3000,
        impact_particles = false,
        bounce = {
          bounciness = 1,
          sound = 31,
          hits = {
            arrows = true,
            crates = true,
            donor_cards = true,
            land = true,
            objects = true,
            water = true,
            worms = true,
            worms_frozen = true,
          },
        },
        explosion = {
          bias = 66,
          power = 80,
        },
        trail = {
          power = 12,
          speed = 30,
          sprite = 80,
        },
      },
      clusters = {
        count = 33,
        launch_power_pct = 8,
        power_variation_pct = 2,
        spread = 360,
        bit = {
          action = "bounce",
          animation = 1,
          flight_sound = 94,
          speed_pct = 100,
          sprite_count = 1,
          bounce = {
            contact_sides = 8,
            sound = 113,
            terrain_keep_speed_pct = 100,
          },
          explosion = {
            bias = 66,
            power = 30,
            push_pct = 100,
          },
          trail = {
            bubbles_per_second = 12.5,
            power = 10,
            speed = 25,
            sprite = 119,
          },
        },
      },
    }
  end,
}
