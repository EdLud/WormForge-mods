-- Mole Shopper launches two stock moles per use. Highlander's placed Mole
-- Bomb remains a separate component with its existing settings.
local holds = require("wf-lib/holds")
local HOLD = "sprites/mole_bombs/hold.png"

return {
  defaults = {ammo = {round_start = -1}, delay = 0},
  install = function(ctx)
    wa.weapons.replace{
      copy_from = "stock.mole_bomb", name = "Mole Bombs", panel_icon = "mole_bomb",
      worm_sprites = holds.PX_POSTURE,
      hold = {sheet = HOLD, frames = 1, thrown = true,
        hand = holds.PX_HANDS[1], hand_type = 1, hand_scale = 1.2,
        hand_radius = -11, hand_rotation = 0, hand_radial_rotation = 0,
        weap_radial_rotation = 0, weap_rotation = 0.5, weap_radius = -11.2},
      -- The source launches at fixed 20% power; holding Space does not charge.
      fires = {type = 1, method = 3, launch_power_pct = 20},
      handling = {shots = 2},
      clusters = {bit = {explosion = {power = 40}}},
    }
    local digging_sprites
    wa.on.missile_frame(function(m)
      if m.weapon ~= ctx.id or m.phase ~= "pre" then return end
      if not digging_sprites then
        local bit = wa.weapons.data(ctx.id).clusters.bit
        local dig = bit.dig
        digging_sprites = {[bit.sprite] = true, [dig.dive_sprite] = true,
          [dig.sprite_1] = true, [dig.sprite_2] = true, [dig.sprite_3] = true}
      end
      -- Classify this weapon's native child directly. No global missile
      -- pointers, coordinate searches or address-keyed lifetime state.
      if digging_sprites[m.sprite] and wa.world.keys().shift and m.vy < 10 then
        m.vy = m.vy + 8
      end
    end)
  end,
}
