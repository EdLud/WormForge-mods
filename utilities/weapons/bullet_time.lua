-- Bullet Time: slows down everything except the active worm (including the turn timer)

local tooltip = require("wf-lib/tooltip")

local RAMP = 2 -- seconds to ease in, and to ease out
local TINT = 0x2060FF -- the screen's tint at full slow motion
local TINT_ALPHA = 0x48
local TINT_SPRITE = "sprites/bullet_time_tint.png"
local MARGIN = 8192 -- pixels of tint past the map's edges

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
    local worm_speed = ctx.option("worm_speed") / 100
    local total = ctx.option("seconds")
    local ramp = math.min(RAMP, total / 2)
    local music = ctx.option("music") and wa.music and wa.music.set_pitch
    local tab = ctx.option("tab") and wa.world.worm_selecting ~= nil
    local tray = tab and wa.hud and wa.hud.tray
    local cells = {} -- team -> its tray entry

    wa.assets.load({ sprites = { TINT_SPRITE } })
    local tint = wa.sprites.key(TINT_SPRITE)

    local t -- real seconds since it was fired; nil while off
    local speed = 1
    local slowed -- the worm on its own time

    local function depth(at)
      if at < ramp then return ease(at / ramp) end
      if at > total - ramp then return 1 - ease((at - (total - ramp)) / ramp) end
      return 1
    end

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

    local function start(worm)
      t = 0
      cell(worm)
      hand_to(worm)
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
        tooltip.notice(worm, string.format("Bullet Time: %.1f s", total - t), 0.1)
      end
    end, { msgs = { wa.msg.FRAME_FINISH } })

    wa.on.turn_start(function(ev)
      retreating = false
      if t and ev.worm then hand_to(ev.worm) end
    end)
    wa.on.turn_retreat(function() retreating = true end)
    wa.on.turn_end(stop)
    wa.on.turn_cleanup(stop)

    local QUAD = {
      points = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
      sprite = tint, color = 0, blend = "alpha", depth = wa.depth.FRONT - 1,
    }
    wa.on.draw(function()
      if not t then return end
      local k = depth(math.min(t + wa.draw.fraction() / (50 * speed), total))
      local alpha = math.floor(TINT_ALPHA * k + 0.5)
      if alpha <= 0 then return end
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
