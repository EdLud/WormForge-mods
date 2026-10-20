-- Cursor Light's selection/lifetime design, with a shared magnetic field.
-- Only synchronized simulation input changes field strength or polarity.
return {
  defaults = { ammo = { round_start = -1 }, delay = 0 },
  install = function(ctx)
    local cursor, field
    local level, attracting, plus_held = 1, true, false
    local RANGE, STRENGTH, MAX_FORCE = 300, 14000, 12

    local function stop()
      if field then field:remove(); field = nil end
      if cursor then cursor:despawn(); cursor = nil end
    end

    local function controls()
      local keys = wa.world.keys()
      local digit = keys.digit
      if digit and digit >= 1 and digit <= 9 and digit ~= level then
        level = digit
        field.strength, field.max_force = STRENGTH * level, MAX_FORCE * level
      end
      if keys.plus_key and not plus_held then
        attracting = not attracting
        field.polarity = attracting and "attract" or "repel"
        field.softening = attracting and 10 or 5
      end
      plus_held = keys.plus_key or false
    end

    local function start(worm, x, y)
      stop()
      if not worm.turn or worm.hp <= 0 then return end
      plus_held = wa.world.keys().plus_key or false
      cursor = wa.cursor.spawn{
        owner = worm, x = x, y = y,
        on = function()
          if not worm.turn or worm.hp <= 0 or worm.weapon ~= ctx.id then
            stop()
            return
          end
          controls()
        end,
      }
      field = wa.magnetism.field{
        source = cursor, range = RANGE,
        strength = STRENGTH * level, max_force = MAX_FORCE * level,
        polarity = attracting and "attract" or "repel",
        softening = attracting and 10 or 5,
      }
      controls()
    end

    wa.weapons.replace{
      copy_from = "stock.teleport",
      name = "Magnet Cursor",
      fires = { aims = true },
      panel_icon = "teleport",
      is_weapon = true,
      eat_fire = true,
      click_finish = false,
      handling = { ends_turn = false },
      on_select = {
        cursor = true,
        on = function(sel) start(sel.worm, sel.x, sel.y) end,
      },
      on_click = function() end,
    }

    wa.on.turn_start(function(ev)
      stop()
      if ev.worm.weapon == ctx.id then
        local p = wa.world.pointer()
        start(ev.worm, p.x, p.y)
      end
    end)
    wa.on.turn_end(stop)
    wa.on.hud(function()
      if cursor and not cursor.dead then
        wa.hud.line(("Magnet Cursor: %s | strength %dx | range %d px | 1-9 strength, + polarity")
          :format(attracting and "ATTRACT" or "REPEL", level, RANGE))
      end
    end)
  end,
}
