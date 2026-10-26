-- A permanent remote light. PX's 60-frame controller is not a reveal timeout.
local lights = require("lib/lights")
local ART = "sprites/far_sight/"

return {
  defaults = {ammo = {round_start = 2}, delay = 0},
  install = function(ctx)
    local terrain_blocking = ctx.option("terrain_blocking")
    local markers = {}
    local cursor
    local function selected(worm)
      return worm and worm.turn and worm.hp > 0 and worm.weapon == ctx.id
        and worm:ammo(ctx.id) ~= 0
    end
    local function stop_cursor()
      if cursor then cursor:despawn(); cursor = nil end
    end
    local function start_cursor(worm, x, y)
      stop_cursor()
      if not selected(worm) then return end
      -- eat_fire suppresses WA's own cursor. This actor follows the pointer
      -- natively and uses the existing cursor render path above the fog.
      cursor = wa.cursor.spawn{owner = worm, x = x, y = y,
        on = function()
          if not selected(worm) then stop_cursor() end
        end}
    end
    wa.weapons.replace{
      copy_from = "stock.teleport",
      name = "Far Sight", panel_icon = ART .. "icon.png", is_weapon = true,
      eat_fire = true, click_finish = false,
      on_select = {cursor = true, on = function(sel)
        start_cursor(sel.worm, sel.x, sel.y)
      end},
      handling = {remember_selection = false, ends_turn = false, retreat = 3000},
      sprites = {ART .. "reveal.png"},
      sounds = {"sounds/far_sight/reveal.wav"},
      params = {gpu_prefix = ART},
      on_click = function(ev)
        local worm = ev.worm
        if not worm or worm.hp <= 0 or worm:ammo(ctx.id) == 0 then return end
        if terrain_blocking and wa.land.solid(ev.x, ev.y) then
          require("wf-lib/tooltip").notice(worm, "Far Sight cannot be placed\ninside terrain.")
          return
        end
        local actor = wa.actors.spawn{
          owner = ev.worm, sprite = false, x = ev.x, y = ev.y,
          gravity = false, collide = false, drown = false, persist = true, solid = false,
        }
        lights.attach(actor, 155, terrain_blocking)
        -- eat_fire keeps WA from firing or spending ammo; accepted placements
        -- consume one unit here. Infinite ammo remains infinite.
        worm:ammo(ctx.id, -1)
        markers[#markers + 1] = {actor = actor, id = actor.id,
          colour = lights.colour(ev.worm), born = wa.world.frame()}
        wa.sound.play(actor, "sounds/far_sight/reveal.wav")
      end,
    }
    wa.on.turn_start(function(ev) start_cursor(ev.worm) end)
    wa.on.turn_end(stop_cursor)
    wa.on.draw(function()
      local tick = wa.world.frame()
      for i = #markers, 1, -1 do
        local marker = markers[i]
        local actor = marker.actor
        if actor.id ~= marker.id then
          table.remove(markers, i)
        else
          local age = tick - marker.born
          for _, ring in ipairs({
            {scale = 0.97 + math.sin(age / 10) * 0.03, turn = age * 0.002},
            {scale = 1 - math.sin(age / 10 + 333) * 0.03, turn = -age * 0.001},
          }) do
            local half, turn = 150 * ring.scale, ring.turn * math.pi * 2
            local s, c = math.sin(turn), math.cos(turn)
            local function point(x, y)
              return {actor.x + x * c - y * s, actor.y + x * s + y * c}
            end
            wa.draw.quad{sprite = ART .. "reveal.png", frame = 0,
              depth = wa.depth.OBJECTS, blend = "add", color = 0xFF000000 | marker.colour,
              points = {point(-half, -half), point(half, -half),
                point(half, half), point(-half, half)}}
          end
        end
      end
    end)
  end,
}
