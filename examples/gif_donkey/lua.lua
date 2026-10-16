-- Growth Hormones, the Lua way: the same weapon as flags.lua, with no status
-- flags. Click and tick are both Lua; native code only runs the verbs you
-- call. Both can be placed at once, each on its own slot.
--
-- Land/explode use the GIF's bottom opaque row as the platform (stock donkey
-- collides on the horizontal rectangle in gfx.dir masks.bmp, not the sprite).
-- a:explode is stock CreateExplosion; bounce is that impulse. Do not zero vy.
-- a.vx = 0 is this weapon's policy: no sideways speed from radial blasts.
return {
  install = function()
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
      copy_from = "stock.grenade",
      name = "Growth Hormones (Lua)",
      is_weapon = true,
      panel_icon = "sprites/icon_lua.png",
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
  end,
}
