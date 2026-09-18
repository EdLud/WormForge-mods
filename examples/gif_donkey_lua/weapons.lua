-- Verbose Lua path. Same weapon as gif_donkey, no status flags.
-- Click and tick are both Lua. Native only runs the verbs you call.
-- Disable Mods/gif_donkey if both are present (same grenade slot).
--
-- Land/explode use the GIF's bottom opaque row as the platform (stock donkey
-- collides on the horizontal rectangle in gfx.dir masks.bmp, not the sprite).
-- a:explode is stock CreateExplosion; bounce is that impulse. Do not zero vy.
-- a.vx = 0 is this weapon's policy: no sideways speed from radial blasts.

local function brain(a)
  a.vx = 0
  a:gravity()
  local hit = a:move({ terrain = true, worms = true })
  if hit.land then
    a:explode({ damage = 50, id = 100, at = "below" })
  end
  a.vx = 0
  a:advance()
  if a:in_water() then
    a:despawn()
  end
end

wa.weapons.replace({
  weapon = "grenade",
  name = "Growth Hormones",
  is_weapon = true,
  sprite = "sprites/200w.gif",

  on_select = {
    cursor = true,
  },

  on_click = function(click)
    wa.actors.spawn({
      sprite = "sprites/200w.gif",
      x = click.x,
      y = click.sky,
      origin = "bottom",
      owner = click.worm,
      on = brain,
    })
  end,
})
