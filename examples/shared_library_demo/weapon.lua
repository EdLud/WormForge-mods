local sprites = require("wf-lib/px_sprite_builder")

return {
  defaults = { ammo = { round_start = -1 }, after_use = "continue" },
  install = function(ctx)
    wa.weapons.replace({
      copy_from = "stock.bazooka",
      worm_sprites = sprites.PX_POSTURE,
      hold = {
        sheet = "sprites/weapon.png", hand = sprites.PX_HANDS[2],
        hand_radius = 12, weap_radius = 8,
      },
      sprites = { "sprites/weapon.png" },
    })
    sprites.flight(ctx, { weapon = ctx.id, sheet = "sprites/weapon.png", anim = "track" })
  end,
}
