-- A stock land cursor with explicit actor light. The profile enables fog;
-- the weapon changes only its own cursor and never the global fog scheme.
return {
  defaults = { ammo = { round_start = -1 }, delay = 0 },
  install = function(ctx)
    local cursor

    local function stop()
      if cursor then
        cursor.light = false
        cursor:despawn()
        cursor = nil
      end
    end

    local function start(worm, x, y)
      stop()
      if not worm.turn or worm.hp <= 0 then return end
      cursor = wa.cursor.spawn{
        owner = worm, x = x, y = y,
        on = function()
          if not worm.turn or worm.hp <= 0 or worm.weapon ~= ctx.id then
            stop()
          end
        end,
      }
      -- Cursors have no default light. An explicit spec enables shadowcasting
      -- for this cursor, using its native pointer position every frame.
      cursor.light = {
        mode = "light", circle = 300, cone = { length = 0 },
        shadow_cast = true, seen_by = "owner", discover = false,
      }
    end

    wa.weapons.replace{
      -- The Teleport: the worm holds the teleporter, and the land cursor is
      -- that weapon's own mode. eat_fire keeps the click from teleporting.
      copy_from = "stock.teleport",
      name = "Cursor Light",
      -- WA's Teleport record isn't remembered between turns; this one is.
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
      -- Clicking keeps the cursor active; no shot, ammo use or terrain write.
      on_click = function() end,
    }

    -- The same weapon may stay selected between turns, without a new select
    -- event. Recreate its cursor for the next active worm in that case.
    wa.on.turn_start(function(ev)
      stop()
      if ev.worm.weapon == ctx.id then
        local p = wa.world.pointer()
        start(ev.worm, p.x, p.y)
      end
    end)
    wa.on.turn_end(stop)
  end,
}
