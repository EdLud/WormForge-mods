-- PX's do_custom_explosion, without the electric taze: falloff damage, push,
-- a crater and one px_effects burst. PX originals:
-- wklua_and_px/utils/custom_explosion.c:17-295. The caller silences WA's own
-- blast (explosion.power = 0) and calls this from on_explode.
--
-- Targets come from wa.world.electrical_nearby, PX's object list in one pass:
-- worms, mines, crates and oil drums. Mines take the same object:hit as drums,
-- so a mine can be set off by the blast.

local M = {}

local EFFECT_KEYS = { "radius", "r", "g", "b", "noise", "duration", "fade",
  "grow", "live", "segments", "thickness", "ellipse", "rebuffer", "smoke",
  "depth", "preset", "owner", "seed", "random" }

local function numbers(o)
  local damage = math.floor(o.damage or o.power or 0)
  local push = o.push or o.push_pct or 0
  local radius = o.radius or (damage + 2) * 2
  local hole = o.hole or o.destroy_radius or damage
  local effect = o.effect_radius or math.floor((damage + 2) / 2)
  return damage, push, radius, hole, effect
end

-- The engine caps the query at 1000 px; bigger blasts walk the groups.
local function targets(x, y, radius)
  local nearby = wa.world and wa.world.electrical_nearby
  if nearby and radius <= 1000 then
    return nearby(x, y, math.max(1, math.ceil(radius)), false)
  end
  local out = {}
  local groups = { wa.worms, wa.mines, wa.crates, wa.oil }
  for i = 1, #groups do
    local list = groups[i] and groups[i].all and groups[i].all() or {}
    for j = 1, #list do out[#out + 1] = list[j] end
  end
  return out
end

local function dead(w)
  return w.state == "dying" or w.state == "drowning" or w.state == "dead"
end

local function play_sound(o)
  local s = o.sound
  if s == nil then return end
  if s == true then s = wa.random(69, 71) end
  if s and s ~= false and o.owner then wa.sound.play(o.owner, s) end
end

-- o = { x, y, damage, push, radius, hole, destroy, owner, sound,
--       effect = false | px_effects burst fields, fx = module }
function M.explode(o)
  o = o or {}
  local x, y = o.x, o.y
  if not x or not y then return 0 end
  local damage, push, radius, hole, effect_radius = numbers(o)
  local fx = o.fx or require("wf-lib/effects/px_effects")
  local hits = 0

  play_sound(o)

  if damage > 0 and radius > 0 then
    local r2 = radius * radius
    for _, obj in ipairs(targets(x, y, radius)) do
      if obj.kind ~= "grave" and not (obj.kind == "worm" and dead(obj)) then
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
            if obj.kind == "worm" then
              obj:hurt{ amount = dmg, vx = px, vy = py }
              hits = hits + 1
            elseif obj.kind == "mine" or obj.kind == "crate"
                or obj.kind == "oil" then
              if obj:hit(dmg, px, py) then hits = hits + 1 end
            end
          end
        end
      end
    end
  end

  if o.destroy ~= false and hole > 0 and fx.crater then
    fx.crater{ x = x, y = y, radius = hole }
  end

  if o.effect ~= false and fx.burst then
    local spec = {}
    local src = type(o.effect) == "table" and o.effect or {}
    for i = 1, #EFFECT_KEYS do
      local k = EFFECT_KEYS[i]
      if src[k] ~= nil then spec[k] = src[k] end
    end
    spec.x, spec.y = x, y
    spec.radius = spec.radius or effect_radius
    spec.owner = spec.owner or o.owner
    fx.burst(spec)
  end
  return hits
end

return M
