-- Power Shotgun: source settings and weapon-scoped art.
local holds = require("wf-lib/holds")
local ART = "sprites/power_shotgun/"

return {
  install = function(ctx)
    wa.weapons.replace{
      copy_from = "stock.shotgun", name = "Power Shotgun", panel_icon = ART .. "icon.png",
      fire_repeat = 5,
      sounds = {"sounds/power_shotgun/fire.wav"},
      worm_sprites = holds.PX_POSTURE,
      hold = {sheet = ART .. "hold.png", sheets = {ART .. "firing.png"}, frames = 1,
        draw_hand = false, hand_radius = -6, hand_rotation = 1, hand_radial_rotation = 0.9,
        weap_radial_rotation = 0, weap_rotation = 1, weap_radius = 0.1},
      handling = {
        remember_selection = false,
      },
      gun = {
        burst_spread_deg = 10,
        damage = 50,
        spread_deg = 20,
        explosion = {
          push_pct = 300,
          variation = 75,
        },
        hits = {
          crates = true,
          donor_cards = true,
          land = true,
          mines = true,
          missiles = true,
          objects = true,
          water = true,
          worms = true,
          worms_frozen = true,
        },
      },
    }
    wa.on.worm_message(function(worm)
      if worm.turn and worm.weapon == ctx.id then
        wa.sound.play(worm, "sounds/power_shotgun/fire.wav")
      end
    end, {msgs = {wa.msg.WEAPON_RELEASED}})
    local chosen = 0
    wa.on.draw(function()
      for _, worm in ipairs(wa.worms.all()) do
        if worm.turn and worm.weapon == ctx.id then
          local sheet = (worm.state == "firing" or worm.state == "fired") and 1 or 0
          if chosen ~= sheet then
            chosen = sheet
            wa.weapons.hold_sheet(ctx.id, sheet)
          end
          break
        end
      end
    end)
  end,
}
