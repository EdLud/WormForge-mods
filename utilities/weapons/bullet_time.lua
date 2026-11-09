-- Bullet Time: fired like +N Seconds (a utility on WA's Double Time, so
-- WA decides when it may be used), it runs the world in slow motion
-- (wa.world.set_speed) for a set time while the turn's worm lives on its
-- own time (worm.time_scale). Projectiles the worm fires are the world's,
-- so they crawl too. Once on it runs out; it cannot be paused.
--
-- Tab fires it too, unless the profile turns that off, without touching the
-- weapon the worm holds: one unit is spent and it starts, mid-jump, on the
-- rope or charging a throw. Only where WA does nothing with Tab: while WA
-- picks worms (the scheme's worm select) Tab is WA's, and under "worm select
-- always" that is the whole turn. Not in the retreat, nor while the weapon's
-- delay runs.
--
-- With Tab on, the turn team's Bullet Time shows in the HUD tray at the top
-- right (wa.hud.tray) with "Tab" under it while the team has any; lit, with
-- the time left as a bar, while it runs.
--
-- The world eases into slow motion and back out of it (easeOutCirc, 2 s
-- each way, inside the duration), and the screen takes a blue tint with it.
-- Firing it sends a ripple out from the worm (wa.view.ripple); the end has
-- none. The soundtrack slows with the world (wa.music.set_pitch) unless the
-- profile turns that off.
-- Time here is real time: a world frame lasts 1 / (50 x the world's speed)
-- seconds. WA's turn clock counts the world's frames, so slow motion
-- stretches the turn in real time.

local tooltip = require("wf-lib/tooltip")

local RAMP = 2            -- seconds to ease in, and to ease out
local TINT = 0x2060FF     -- the screen's tint at full slow motion
local TINT_ALPHA = 0x48
local TINT_SPRITE = "sprites/bullet_time_tint.png"
local MARGIN = 8192       -- pixels of tint past the map's edges

-- easeOutCirc: fast at first, settling at the end. Only + - * / and sqrt,
-- the same on every machine.
local function ease(x)
  local d = x - 1
  return math.sqrt(1 - d * d)
end

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
    -- The worm's speed in real time; its scale is against the world's.
    local worm_speed = ctx.option("worm_speed") / 100
    local total = ctx.option("seconds")
    local ramp = math.min(RAMP, total / 2)
    -- Presentation only, like the tint; a WormForge without it plays on.
    local music = ctx.option("music") and wa.music and wa.music.set_pitch
    local tab = ctx.option("tab") and wa.world.worm_selecting ~= nil
    -- Presentation only; a WormForge without it plays on.
    local tray = tab and wa.hud and wa.hud.tray
    local cells = {}   -- team -> its tray entry

    wa.assets.load({ sprites = { TINT_SPRITE } })
    local tint = wa.sprites.key(TINT_SPRITE)

    local t        -- real seconds since it was fired; nil while off
    local speed = 1
    local slowed   -- the worm on its own time

    -- How far into slow motion at `at` seconds: 0 none, 1 all of it.
    local function depth(at)
      if at < ramp then return ease(at / ramp) end
      if at > total - ramp then return 1 - ease((at - (total - ramp)) / ramp) end
      return 1
    end

    -- The team's cell in the tray while it has any Bullet Time; the engine
    -- drops it once the team has none (and it isn't lit).
    local function cell(worm)
      if not tray then return nil end
      local e = cells[worm.team]
      if e and e:is_open() then return e end
      if worm:ammo(id) == 0 then return nil end
      e = tray.add{ weapon = id, team = worm.team, key = "Tab" }
      cells[worm.team] = e
      return e
    end

    local function apply()
      speed = 1 + (world - 1) * depth(t)
      wa.world.set_speed(speed)
      if music then music(speed) end
      if slowed then slowed.time_scale = math.min(worm_speed / speed, 8) end
      local e = slowed and cells[slowed.team]
      if e then e:set{ lit = true, progress = 1 - t / total } end
    end

    local function hand_to(worm)
      if slowed and slowed.id ~= worm.id then slowed.time_scale = 1 end
      slowed = worm
      apply()
    end

    -- Slow motion starts for `worm`; the ripple goes out from it.
    local function start(worm)
      t = 0
      cell(worm)
      hand_to(worm)
      -- Presentation only, so a simulation callback may start it on every
      -- machine. Its time is real time, so slow motion leaves it alone.
      if wa.view and wa.view.ripple then
        wa.view.ripple{
          x = worm.x,
          y = worm.y,
          amplitude = 10,
          wavelength = 64,
          speed = 60,
          duration_ms = 4200,
          falloff = 120,
        }
      end
    end

    local function stop()
      if not t then return end
      t, speed = nil, 1
      if slowed then
        slowed.time_scale = 1
        local e = cells[slowed.team]
        if e then e:set{ lit = false, progress = false } end
      end
      slowed = nil
      wa.world.set_speed(1)
      if music then music(1) end
    end

    wa.weapons.replace({
      copy_from = "stock.double_turn_time",
      name = "Bullet Time",
      panel_icon = "sprites/bullet_time.png",
      on_fire = function(fire)
        -- Native firing spends one unit. Refund it while one is running, or
        -- on a WormForge without the verbs.
        if t or not wa.world.set_speed then
          if not wa.world.set_speed then
            wa.log("bullet time: this WormForge has no wa.world.set_speed")
          end
          if fire.worm:ammo(id) >= 0 then fire.worm:ammo(id, 1) end
          return
        end
        start(fire.worm)
      end,
    })

    -- Tab: the synchronized key, so every machine starts it on the same frame.
    local tab_held = false
    local retreating = false
    if tab then
      wa.on.worm_message(function(worm)
        if not worm.turn then return end
        cell(worm)
        local held = wa.world.keys().tab
        local pressed = held and not tab_held
        tab_held = held
        if not pressed or t or retreating then return end
        if wa.world.worm_selecting() then return end
        -- A delay counting down, or -1, blocks it as it blocks the panel.
        if worm:ammo(id) == 0 or worm:delay(id) ~= 0 then return end
        worm:ammo(id, -1)
        start(worm)
      end, { msgs = { wa.msg.FRAME_FINISH } })
    end

    wa.on.worm_message(function(worm)
      if not t or not worm.turn then return end
      t = t + 1 / (50 * speed)
      if t >= total then
        stop()
      else
        apply()
        -- The time left, in the weapon tooltip's window (bottom right, the
        -- team's colour), over the held weapon's hint, which it gets back a
        -- few frames after the end.
        tooltip.notice(worm, string.format("Bullet Time: %.1f s", total - t), 0.1)
      end
    end, { msgs = { wa.msg.FRAME_FINISH } })

    -- A worm switch (Tab) hands the turn on: the new worm takes it over.
    wa.on.turn_start(function(ev)
      retreating = false
      if t and ev.worm then hand_to(ev.worm) end
    end)
    wa.on.turn_retreat(function() retreating = true end)
    wa.on.turn_end(stop)
    wa.on.turn_cleanup(stop)

    -- The tint over the whole screen, in front of the world and its water,
    -- behind the HUD; between world frames it eases on with the fraction.
    local QUAD = {
      points = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
      sprite = tint, color = 0, blend = "alpha", depth = wa.depth.FRONT - 1,
    }
    wa.on.draw(function()
      if not t then return end
      local k = depth(math.min(t + wa.draw.fraction() / (50 * speed), total))
      local alpha = math.floor(TINT_ALPHA * k + 0.5)
      if alpha <= 0 then return end
      -- The whole map and a wide margin round it, whatever the camera or
      -- zoom: only what is on screen is filled.
      local size = wa.world.size()
      local x0, y0, x1, y1 = -MARGIN, -MARGIN, size.w + MARGIN, size.h + MARGIN
      local p = QUAD.points
      p[1][1], p[1][2] = x0, y0
      p[2][1], p[2][2] = x1, y0
      p[3][1], p[3][2] = x1, y1
      p[4][1], p[4][2] = x0, y1
      QUAD.color = (alpha << 24) | TINT
      wa.draw.quad(QUAD)
    end)
  end,
}
