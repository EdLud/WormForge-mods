-- Bullet Time: fired like +N Seconds (a utility on WA's Double Time, so
-- WA decides when it may be used), it runs the world in slow motion
-- (wa.world.set_speed) for a set time while the turn's worm lives on its
-- own time (worm.time_scale). Projectiles the worm fires are the world's,
-- so they crawl too. Once on it runs out; it cannot be paused.
--
-- WA's turn clock counts the world's frames, so slow motion stretches the
-- turn in real time.

return {
  defaults = {
    ammo = { round_start = 0 },
    delay = 0,
    crate = { type = "utility" },
    after_use = "continue",
  },
  install = function(ctx)
    local id = ctx.id
    local world = ctx.option("world_speed") / 100
    -- The worm's speed is in real time; its scale is against the world's.
    local scale = math.min(ctx.option("worm_speed") / 100 / world, 8)
    -- Its length in world frames: real seconds at 50 frames a second, slowed.
    local length = math.floor(ctx.option("seconds") * 50 * world)

    local left = 0   -- world frames of slow motion left
    local slowed     -- the worm on its own time

    local function hand_to(worm)
      if slowed and slowed.id ~= worm.id then slowed.time_scale = 1 end
      slowed = worm
      worm.time_scale = scale
    end

    local function stop()
      if not slowed then return end
      left = 0
      slowed.time_scale = 1
      slowed = nil
      wa.world.set_speed(1)
    end

    wa.weapons.replace({
      copy_from = "stock.double_turn_time",
      name = "Bullet Time",
      panel_icon = "sprites/bullet_time.png",
      on_fire = function(fire)
        -- Native firing spends one unit. Refund it while one is running, or
        -- on a WormForge without the verbs.
        if left > 0 or not wa.world.set_speed then
          if not wa.world.set_speed then
            wa.log("bullet time: this WormForge has no wa.world.set_speed")
          end
          if fire.worm:ammo(id) >= 0 then fire.worm:ammo(id, 1) end
          return
        end
        left = length
        wa.world.set_speed(world)
        hand_to(fire.worm)
      end,
    })

    wa.on.worm_message(function(worm)
      if left == 0 or not worm.turn then return end
      left = left - 1
      if left == 0 then stop() end
    end, { msgs = { wa.msg.FRAME_FINISH } })

    -- A worm switch (Tab) hands the turn on: the new worm takes it over.
    wa.on.turn_start(function(ev)
      if left > 0 and ev.worm then hand_to(ev.worm) end
    end)
    wa.on.turn_end(stop)
    wa.on.turn_cleanup(stop)

    wa.on.hud(function()
      if left > 0 then
        wa.hud.line(string.format("Bullet Time: %.1f s", left / 50 / world))
      end
    end)
  end,
}
