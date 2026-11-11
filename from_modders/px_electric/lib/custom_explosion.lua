-- PX's electric explosion: damage, push, taze, hole and effect in one call.

local M = {}

local EFFECT_KEYS = { "radius", "r", "g", "b", "noise", "duration", "fade",
  "grow", "live", "segments", "thickness", "ellipse", "rebuffer", "smoke",
  "depth", "preset", "owner", "seed", "random" }

local function numbers(o)
  local damage = math.floor(o.damage or 0)
  local push = o.push or o.push_power or 0
  local radius = o.radius or (damage + 2) * 2
  local hole = o.hole or o.destroy_radius or damage
  local effect = o.effect_radius or math.floor((damage + 2) / 2)
  return damage, push, radius, hole, effect
end

function M.electric(o)
  o = o or {}
  local x, y = o.x, o.y
  if not x or not y then return 0 end
  local damage, push, radius, hole, effect_radius = numbers(o)
  local zap = o.zap or require("lib/electric_damage")
  local fx = o.fx or require("wf-lib/effects/px_effects")
  local hits = 0

  if damage > 0 and radius > 0 then
    local zero = {}
    for _, w in ipairs(wa.worms.all()) do
      if w.hp <= 0 then zero[w.id] = true end
    end
    hits = wa.world.blast{ owner = o.owner, x = x, y = y, damage = damage,
      radius = math.ceil(radius), push_pct = push, kind = o.kind or "taze" }
    local r2 = radius * radius
    for _, obj in ipairs(wa.worms.all()) do
      local live = not zap.can_affect or zap.can_affect(obj)
      if live then
        local dx, dy = obj.x - x, obj.y - y
        local d2 = dx * dx + dy * dy
        if d2 < r2 then
          local dist = math.sqrt(d2)
          local dmg = math.floor(damage * (radius - dist) / radius)
          if dmg > 0 then
            local px, py = 0, 0
            if dist > 0.001 then
              local force = (dmg / 5) * (push / 100)
              px, py = dx / dist * force, dy / dist * force
            end
            if o.taze ~= false then
              zap.taze(obj, { frames = o.taze_frames or 20,
                push_x = px, push_y = py })
            elseif zero[obj.id] then
              obj:hurt{ amount = dmg, vx = px, vy = py }
              hits = hits + 1
            end
          end
        end
      end
    end
  end

  if o.destroy ~= false and hole > 0 and fx.crater then
    fx.crater{ x = x, y = y, radius = hole } -- MakeHole
  end

  if o.chain ~= false and fx.arc then
    local cr = o.chain_radius or radius
    local cr2 = cr * cr
    for _, mine in ipairs(wa.mines.all()) do
      local dx, dy = mine.x - x, mine.y - y
      if dx * dx + dy * dy < cr2 then
        fx.arc{ from = { mine.x, mine.y }, to = { x, y },
          bulge = 5, speed = 0.079, terrain = false, owner = o.owner }
      end
    end
  end

  if o.effect ~= false and fx.burst then
    local spec = {}
    local src = o.effect
    if type(src) == "table" then
      for i = 1, #EFFECT_KEYS do
        local k = EFFECT_KEYS[i]
        if src[k] ~= nil then spec[k] = src[k] end
      end
    end
    spec.x, spec.y = x, y
    spec.radius = spec.radius or effect_radius
    spec.owner = spec.owner or o.owner
    fx.burst(spec)
  end
  return hits
end

return M
