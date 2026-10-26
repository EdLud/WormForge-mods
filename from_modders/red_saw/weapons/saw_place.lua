-- PX's saw place record (saw_place_wep.wep). It is the weak-throw/mine-style
-- version; the record's own explosion is power 0, and the saw still comes from
-- on_explode. Size is the component option, default 50%.
local saw = require("lib/saw")
local sprites = require("wf-lib/px_sprite_builder")

return {
  defaults = { ammo = { round_start = -1 }, delay = 0 },
  install = function(ctx)
    local size = (ctx.option("size") or 50) / 100
    saw.install(ctx)
    wa.weapons.replace{
      wep = "weps/saw_place.wep",
      panel_icon = "sprites/saw/icon_place.png",
      sprite = "sprites/saw/foldedblades.png",
      sprites = {
        "sprites/saw/sawsheet.png",
        "sprites/saw/foldedblades.png",
      },
      sounds = {
        "sounds/saw/saw_cut_1.wav",
        "sounds/saw/saw_cut_2.wav",
        "sounds/saw/saw_cut_3.wav",
        "sounds/saw/saw_cut_4.wav",
        "sounds/saw/clank-sound.wav",
        "sounds/saw/electric-shock.wav",
      },
      --params = { gpu_prefix = "sprites/saw/" },
      hold = {
        thrown = true,
        sheet = "sprites/saw/foldedblades.png",
        hand = sprites.PX_HANDS[1], -- PX hand_type 1: the lower hand
        hand_scale = 0.8,
        hand_radius = 20,
        hand_rotation = 1,
        hand_radial_rotation = 1,
        weap_rotation = -3,
        weap_radius = 10,
        weap_radial_rotation = 0.9,
      },
      worm_sprites = sprites.PX_POSTURE,
      on_explode = function(ev)
        saw.on_weapon_explode(ev, size,
          "sounds/saw/saw_cut_1.wav", "sounds/saw/saw_cut_2.wav")
      end,
    }
  end,
}
