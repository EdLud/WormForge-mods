-- Magnetic Missile: a magnet fired like a bazooka; it sticks where it hits the land nose first.

local magnet = require("lib/magnet")
local weapon = {}

weapon.requires = { "lib/magnet" }

local ID = "px.magnetic_missile"
local ART = "sprites/magnetic_missile/"
local BEAM = "sprites/px_effects/beam.png"

weapon.definition = {
  wep = "weps/barrel_launcher.wep",
  name = "Magnetic Missile",
  panel_icon = ART .. "ico_magmissile.png",
  sprites = { ART .. "magmissile.png", ART .. "magmissile2.png", BEAM, table.unpack(magnet.sprites) },
  params = { gpu_prefix = "sprites/" },
  on_fire = function(fire) require("lib/shared").fires.magnetic_missile(fire) end,
}

function weapon.setup()
  local shared = require("lib/shared")
  local TURNS, HEALTH = 3, 20
  local BOOM = { id = 100, damage = 40, below = false }
  local FIELD = { range = 120, strength = 12000, max_force = 12, attract_softening = 20, repel_softening = 10 }
  local RING = { max = 60, speed = 0.8, gap = 23, cycle = 69 }
  local BEHIND = 14 -- the field sits this far behind the nose
  local AHEAD = 8 -- land this far ahead of the nose holds it
  local BOUNCE_SPEED, PUNCH_SPEED, PUNCH = 5, 0.5, 0.3
  local STICK_SOUND, PUNCH_SOUND = 28, 101
  local SINK, SUNK = 1 / 2, 200
  local FLYING, STUCK, LOOSE = 0, 1, 2
  local PUSHED_BY = { mines = 0, missiles = 0 }

  magnet.toggle_with(ID)

  local function sq(v) return v * v end

  local function land_ahead(m)
    local dx, dy = wa.math.cos(m.angle), wa.math.sin(m.angle)
    local hit = wa.world.trace({ x0 = m.x, y0 = m.y, x1 = m.x + dx * AHEAD, y1 = m.y + dy * AHEAD,
      radius = 2, with = { "terrain" } })
    return hit ~= nil
  end

  local function stick(m, a)
    m.phase, m.ax, m.ay = STUCK, a.x, a.y
    m.ignore_damage = false
    a.gravity = 0
    a:warp({ x = a.x, y = a.y, vx = 0, vy = 0 })
    wa.sound.play(a, STICK_SOUND)
  end

  local function loosen(m, a)
    m.phase, m.ignore_damage = LOOSE, false
    a.gravity = 1
  end

  local function contact(m, a, ev)
    if m.phase ~= FLYING then return end
    local speed = math.sqrt(sq(ev.vx) + sq(ev.vy))
    if ev.other == "land" then
      if land_ahead(m) then stick(m, a)
      elseif speed <= BOUNCE_SPEED then loosen(m, a) end
      return
    end
    local kind = type(ev.other) == "table" and ev.other.kind
    if kind == "worm" and speed > PUNCH_SPEED then
      ev.other:hit({ amount = 0, vx = ev.vx * PUNCH, vy = (ev.vy - speed) * PUNCH })
      wa.sound.play(a, PUNCH_SOUND)
      m.through = { ev.vx, ev.vy } -- it flies on through
    else
      loosen(m, a)
    end
  end

  local function hit(m, a, event)
    if m.phase == STUCK then
      local melee = event.kind ~= "blast" and event.kind ~= "bullet" and event.kind ~= "fire"
      if melee or not land_ahead(m) then loosen(m, a) end
    end
    magnet.hit(m, a, event)
  end

  local function frame(m, a)
    m.age = m.age + 1
    if m.through then
      a:warp({ x = a.x, y = a.y, vx = m.through[1], vy = m.through[2] })
      m.through = nil
    end
    if m.phase == STUCK then a:warp({ x = m.ax, y = m.ay, vx = 0, vy = 0 }) end
    if not m.sinking then m.x, m.y, m.vx, m.vy = a.x, a.y, a.vx, a.vy end
    if m.y >= wa.world.water() then
      magnet.discharge(m)
      if not m.sinking then m.sinking = true; a.hits = {} end
      m.vx, m.vy, m.y = 0, 0, m.y + SINK
      a:warp({ x = m.x, y = m.y, vx = 0, vy = 0 })
      if m.y >= wa.world.water() + SUNK then
        magnet.remove(m)
        a:remove()
        return
      end
    end
    if m.health <= 0 then
      magnet.trigger_mines(m)
      magnet.remove(m)
      a:explode(BOOM)
      a:remove()
      return
    end
    if m.phase == FLYING then
      if m.vx ~= 0 or m.vy ~= 0 then m.angle = wa.math.atan(m.vy, m.vx) end
      if m.trail then m.trail:push(m.x, m.y) end
    else
      if m.trail then m.trail:finish(); m.trail = nil end
      if m.phase == LOOSE then
        local speed = math.sqrt(sq(m.vx) + sq(m.vy))
        m.angle = m.angle + (m.vx < 0 and -1 or 1) * math.min(0.5, 0.04 * speed)
      end
    end
    m.field_x = m.x - wa.math.cos(m.angle) * BEHIND
    m.field_y = m.y - wa.math.sin(m.angle) * BEHIND
    m.field:move(m.field_x, m.field_y)
    if m.turns > 0 then
      m.field.native = not (m.ended_at and m.age - m.ended_at >= 300)
      magnet.trigger_mines(m)
      m.spark = (m.spark + 0.02) % 1.4
    end
    -- The art points up: a quarter turn on from the way it flies.
    a:gfx({ angle = (math.deg(m.angle) + 90) % 360, depth = wa.depth.OBJECTS })
  end

  shared.fires.magnetic_missile = function(fire)
    local worm = fire.worm
    local pol = magnet.polarity(worm)
    local m = { pol = pol, turns = TURNS, health = HEALTH, phase = FLYING, ignore_damage = true,
      x = fire.x, y = fire.y, vx = fire.vx, vy = fire.vy, angle = wa.math.atan(fire.vy, fire.vx) }
    local a = wa.actors.spawn({
      sprite = ART .. (pol < 0 and "magmissile.png" or "magmissile2.png"),
      x = m.x, y = m.y, vx = m.vx, vy = m.vy, owner = worm, gravity = 1,
      body = { hits = { land = true, worms = true, objects = true }, pushed_by = PUSHED_BY },
      on = {
        frame = function(actor) frame(m, actor) end,
        hit = function(actor, event) hit(m, actor, event) end,
        contact = function(actor, ev) contact(m, actor, ev) end,
      },
    })
    a:collision_ignore(worm, true)
    m.a, m.team = a, worm.team
    magnet.add(m, { range = FIELD.range, strength = FIELD.strength, max_force = FIELD.max_force,
      attract_softening = FIELD.attract_softening, repel_softening = FIELD.repel_softening,
      at = { m.x, m.y } }, RING)
    m.trail = wa.draw.trail and wa.draw.trail({ sprite = BEAM, width = 6, max = 15,
      color = pol < 0 and 0xFFC83C3C or 0xFF3C50BE, blend = "add" })
  end

  require("lib/weapon_hint").register(ID, function(worm)
    return magnet.polarity(worm) < 0 and "Magnetic Missile: ATTRACT\n+ to repel"
      or "Magnetic Missile: REPEL\n+ to attract"
  end)
end

return weapon
