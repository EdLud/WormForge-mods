-- Magnets: a field that pulls or pushes mines and missiles for some turns,
-- set off mines it holds, health, the + key's polarity and the rings drawn
-- round it. The Electromagnet's and the Magnetic Missile's.

local on_missile = require("lib/on_missile")

local magnet = {}

local SYNC_FACTOR = 4 -- MaxSyncRange: MaxRange * 0.25, squared
local RELEASE_AFTER = 300
local DAMPED = { ["px.hellish_hand_grenade"] = true }
local DAMPING = 0.985
local BODY = "sprites/electromagnet/"
local RING_IN, RING_OUT, SPARKS = BODY .. "ring_in.png", BODY .. "ring_out.png", BODY .. "magnetsparks.png"

magnet.sprites = { BODY .. "ring_in.png", BODY .. "ring_out.png", BODY .. "magnetsparks.png" }

local magnets = {}
local polarity = {}
local plus_held = {} -- worm id -> the synchronized + key last frame
local toggled_by = {} -- weapon ids whose + key switches the worm's polarity

local function trunc(x) return x >= 0 and math.floor(x) or -math.floor(-x) end

-- The worm's polarity: -1 attracts, 1 repels. One for all its magnets.
function magnet.polarity(worm)
  return polarity[worm.id] or 1
end

-- The + key switches the worm's polarity while it holds this weapon.
function magnet.toggle_with(id)
  toggled_by[id] = true
end

local function trigger_mine(m, mine, mines)
  local fuse = mine.fuse
  if fuse < 0 then
    fuse = wa.random(1000, 4999)
    if m.pol < 0 then
      local longest = 1000
      for _, other in ipairs(mines) do
        if other.id ~= mine.id then
          local dx, dy = (other.x - m.x), (other.y - m.y)
          if dx * dx + dy * dy < m.sync2 then longest = math.max(longest, other.fuse) end
        end
      end
      if longest > 1000 then fuse = longest + wa.random(-200, 199) end
    end
  end
  mine:arm(fuse)
end

function magnet.trigger_mines(m)
  if not (m.ended_at and m.age - m.ended_at > RELEASE_AFTER) then
    local mines = wa.mines.all()
    for _, mine in ipairs(mines) do
      if m.field:contains(mine.x, mine.y) then
        trigger_mine(m, mine, mines)
      end
    end
  end
end

function magnet.remove(m)
  m.alive = false
  m.field:remove()
  for i, other in ipairs(magnets) do
    if other == m then table.remove(magnets, i); break end
  end
end

function magnet.discharge(m)
  if m.turns <= 0 then return end
  magnet.trigger_mines(m)
  m.field.enabled = false -- also wakes custom sleepers for one simulation step
  m.turns = 0
end

local function recharge(m)
  if not m.alive or m.sinking then return end
  if m.turns <= 0 then m.field.enabled = true end
  m.turns = m.max_turns
end

-- A hit on the magnet's body: its health takes the damage, its body the push.
function magnet.hit(m, a, event)
  local damage = math.max(0, event.damage or 0)
  if event.kind == "blast" and damage > 0 then
    local dx, dy = (a.x - (event.x or a.x)), (a.y - (event.y or a.y))
    damage = trunc((1 - (dx * dx + dy * dy) / (damage * damage * 4)) * damage)
  elseif event.kind == "percent" then
    damage = trunc(m.health * damage / 100)
  end
  if damage > 0 and not m.ignore_damage then m.health = m.health - damage end
  local vx, vy = event.vx or 0, event.vy or 0
  if vx ~= 0 or vy ~= 0 then
    a:warp { x = a.x, y = a.y, vx = a.vx + vx, vy = a.vy + vy }
  end
end

-- A new magnet. `m` holds its state (pol, team, turns, health, x, y, a: its
-- body); `field` the field's numbers, on the body, or at `at` = { x, y }
-- for a field its magnet moves itself (`m.field:move`); `ring` the rings:
-- largest radius, pixels a frame, frames between rings and frames before
-- one starts again.
function magnet.add(m, field, ring)
  m.max_turns, m.max_health = m.turns, m.health
  m.age, m.spark, m.angle, m.alive = 0, 0, m.angle or 0, true
  m.sync2 = field.range * field.range // SYNC_FACTOR
  m.ring = ring or { max = 120, speed = 0.8, gap = 65, cycle = 195 }
  local spec = { range = field.range,
    strength = field.strength, max_force = field.max_force,
    softening = m.pol < 0 and field.attract_softening or field.repel_softening,
    polarity = m.pol < 0 and "attract" or "repel" }
  if field.at then spec.x, spec.y = field.at[1], field.at[2] else spec.source = m.a end
  m.field = wa.magnetism.field(spec)
  magnets[#magnets + 1] = m
  return m
end

local radius_of = 8 -- a magnet's reach for the Tazer's arc

function magnet.setup()
  magnets, polarity, plus_held = {}, {}, {}

  require("lib/electrical").register({
    kind = "magnet",
    targets = function()
      local out = {}
      for _, m in ipairs(magnets) do
        if m.alive and not m.sinking and m.a then
          out[#out + 1] = { id = m.a.id, x = m.x, y = m.y, radius = radius_of, m = m }
        end
      end
      return out
    end,
    zap = function(obj, side)
      local m = obj.m
      if not m.alive then return end
      if m.turns <= 0 then recharge(m); return end
      m.health = 1
      magnet.hit(m, m.a, { damage = 12, vx = side * 1.2, vy = -4 })
    end,
    strike = function(obj) recharge(obj.m) end,
  })

  local turn_open = false
  wa.on.turn_start(function(event)
    if turn_open then return end
    turn_open = true
    for i = #magnets, 1, -1 do
      if magnets[i].field.native == nil then magnet.remove(magnets[i]) end -- the engine freed it (far off the map)
    end
    local team = event.worm and event.worm.team
    for _, m in ipairs(magnets) do
      m.ended_at = nil
      m.field.native = true
      if m.alive and m.team == team and m.turns > 0 then
        if m.turns == 1 then magnet.discharge(m) else m.turns = m.turns - 1 end
      end
    end
  end)

  wa.on.turn_end(function()
    turn_open = false
    for _, m in ipairs(magnets) do m.ended_at = m.age end
  end)

  on_missile(function(missile)
    if missile.phase ~= "pre" or not DAMPED[missile.weapon] then return end
    for _, m in ipairs(magnets) do
      if m.field:contains(missile.x, missile.y) then
        missile.vx, missile.vy = missile.vx * DAMPING, missile.vy * DAMPING
        return
      end
    end
  end, { weapons = wa.sorted(DAMPED), phase = "pre" })

  wa.on.worm_message(function(worm)
    local id = worm.id
    local pressed = worm.turn and toggled_by[worm.weapon] and wa.world.keys().plus_key or false
    if pressed and not plus_held[id] then polarity[id] = -(polarity[id] or 1) end
    plus_held[id] = pressed
  end, { msgs = { wa.msg.FRAME_FINISH } })

  if wa.on.draw and wa.draw.quad then
    local health_label = require("lib/sentry_health")
    health_label.install()
    local QUAD = { blend = "add", points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} } }
    local function square(sprite, frame, color, depth, x, y, h, angle)
      QUAD.sprite, QUAD.frame, QUAD.color, QUAD.depth = sprite, frame, color, depth
      local c, s = wa.math.cos(angle) * h, wa.math.sin(angle) * h
      local p = QUAD.points
      p[1][1], p[1][2] = x - c + s, y - s - c
      p[2][1], p[2][2] = x + c + s, y + s - c
      p[3][1], p[3][2] = x + c - s, y + s + c
      p[4][1], p[4][2] = x - c - s, y - s + c
      wa.draw.quad(QUAD)
    end
    wa.on.draw(function()
      for _, m in ipairs(magnets) do
        if m.alive and not m.sinking and m.show_health ~= false then
          health_label.draw(m.health, m.max_health, m.x, m.y - 15, wa.depth.OBJECTS - 2)
        end
        if m.alive and m.turns > 0 then
          local x, y = m.field_x or m.x, m.field_y or m.y
          local ring = m.pol < 0 and RING_IN or RING_OUT
          local r = m.ring
          local top = r.max
          for phase = 0, 2 do
            local t = (m.age - phase * r.gap) % r.cycle
            local radius = m.pol < 0 and top - r.speed * t or 5 + r.speed * t
            if radius >= 5 and radius <= top then
              local alpha = math.max(0, math.min(255, math.floor((top - radius) * 255 / top)))
              square(ring, nil, (alpha << 24) | 0xFFFFFF, wa.depth.OBJECTS + 1, x, y, radius, 0)
            end
          end
          if m.spark <= 1 then
            square(SPARKS, math.min(9, math.floor(m.spark * 10)), nil, wa.depth.OBJECTS - 1, x, y, 13, m.angle)
          end
        end
      end
    end)
  end
end

return magnet
