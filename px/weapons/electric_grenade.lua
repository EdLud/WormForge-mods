-- Electric Grenade: record, art and behaviour.
local weapon = {}

-- Native record settings. Edit this weapon here; imported records are review drafts.
weapon.record = {
  handling = {
    remember_selection = true,
    ends_turn = true,
  },
}

weapon.missile_sprite = { -- Electric Grenade (electric_grenade_anim: electric_grenade_bullet)
    sheet = "sprites/px_hold/electric_grenade.png", frames = 1,
    spin = true, -- its record's WAT_Rotation
    -- PX's record has sprite 0; the pack's stock grenade is only for the
    -- worm's throw sheet.
    hide = true,
  }

function weapon.definition()
  local shared = require("lib/shared")
  local sdk = require("wf-lib/holds")
  local PX_POSTURE, PX_HANDS = sdk.PX_POSTURE, sdk.PX_HANDS
  return require("lib/weapon").merge(weapon.record, {
    wep = "weps/earthquake.wep",
    panel_icon = "sprites/electric_grenade/icon.png",
    sprite = "grenade",
    worm_sprites = PX_POSTURE,
    sprites = { "sprites/px_hold/electric_grenade.png" },
    sounds = { "sounds/lightning/tazer_loop.wav" },
    params = { gpu_prefix = "sprites/px_hold/" },
    on_explode = function(ev) require("lib/electrical").context().grenade_arc(ev) end,
    hold = { -- Electric Grenade (electric_grenade_anim)
        thrown = true,
        sheet = "sprites/px_hold/electric_grenade.png", hand_type = 1,
        hand_radius = 15, hand_scale = 0.8,
        weap_rotation = 0.5, weap_radius = 9,
        hand = PX_HANDS[1],
    },
  })
end

weapon.requires = { "lib/electrical" }

function weapon.setup()
  local c = require("lib/electrical").context()
  local tazed = c.tazed

  -- The worm that last fired the Electric Grenade, as PX keeps it at the
  -- fire: the grenade's arc never zaps its thrower (lib/electrical's
  -- grenade_arc). A tazed worm's fire is eaten there and throws nothing.
  wa.on.worm_message(function(worm, msg)
    if worm.weapon == "px.electric_grenade" and not tazed["worm:" .. worm.id] then
      c.thrower = worm
    end
  end, { msgs = { wa.msg.FIRE_WEAPON } })
end

return weapon
