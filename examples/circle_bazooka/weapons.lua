-- Proof pack: stock bazooka slot, PNG ball strip (8 frames), lighter gravity / more wind.
--
-- params.sprite is a pack-relative PNG, 1 row x sprite_columns frames.
-- Encoded as a WA .spr and installed like PX LoadSprite in InitGraphic.
-- Colours are matched onto the current map palette (256 slots, map-dependent).
--
-- Do not enable ice_bazooka at the same time — first loaded id keeps the slot.

wa.weapons.register({
  id = "example.circle_bazooka",
  based_on = "bazooka",
  name = "Circle Bazooka",
  params = {
    sprite = "sprites/ball.png",
    sprite_columns = 8,
    gravity_pct = 25,
    wind_pct = 200,
    bounce_pct = 100,
  },
})

local prev_vy = {}
local FALL = 2 * 0x10000

-- Only this pack's bazooka: do not enable wind on every missile (donkey, etc).

wa.on.gravity_after(function(p)
  local last = prev_vy[p.id]
  if last and last > FALL and p.vy < 0 then
    p.vy = p.vy + p.vy // 4
  end
  prev_vy[p.id] = p.vy
end)

wa.on.hud(function()
  wa.hud.line("circle bazooka  g=25  wind=200")
end)
