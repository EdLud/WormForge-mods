-- A placed, seven-second fragmentation bomb with 28 impact-detonating children.
local holds = require("wf-lib/holds")
local ART = "sprites/j_bomb/"

return {
  install = function()
    wa.weapons.replace{
      copy_from = "stock.dynamite", name = "j-bomb", panel_icon = ART .. "icon.png",
      sprite = ART .. "body.png",
      cluster = {sprite = ART .. "fragment.png", sprite_columns = 1},
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
        countdown = 7000,
        fuse = 7000,
        explosion = {
          power = 80,
        },
        trail = {
          power = 5,
          speed = 15,
          sprite = 114,
        },
      },
      clusters = {
        count = 28,
        launch_power_pct = 166,
        power_variation_pct = 150,
        spread = 360,
        bit = {
          animation = 5,
          fuse = 2000,
          gravity_pct = 100,
          speed_pct = 150,
          sprite_count = 1,
          ends_on_contact = {
            arrows = true,
            crates = true,
            donor_cards = true,
            land = true,
            objects = true,
            water = true,
            worms = true,
            worms_frozen = true,
          },
          explosion = {
            bias = 50,
            power = 30,
            push_pct = 100,
            variation = 10,
          },
          trail = {
            bubbles_per_second = 12.5,
            power = 25,
            speed = 50,
            sprite = 119,
          },
        },
      },
    }
  end,
}
