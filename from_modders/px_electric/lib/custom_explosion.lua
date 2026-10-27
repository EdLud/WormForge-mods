-- PX's custom explosion, for electric weapons: damage, push, a taze, the hole
-- and the electric effect in one call. Ports do_custom_explosion
-- (wklua_and_px/utils/custom_explosion.c:17-295); the electric mine reaches it
-- through do_cus_exp_electric (custom_taze.c:308-324). It replaces WA's blast,
-- so the caller silences its own (a mine's `explosion.power = 0` is 0 damage
-- and 0 radius). PX applies the mine's damage twice (weapon_electric_mine.c:97
-- and :98); this applies it once.
--
-- The damage loop uses PX's object list, as electric grenade and lightning
-- strike do: wa.world.electrical_nearby finds worms, mines, crates and oil
-- drums in one pass. Crates and drums take the falloff damage through
-- obj:hit (custom_explosion.c:103-124); mines keep the separate chain arcs
-- below instead, until tazing one becomes its own change.

local M = {}

-- The px_effects burst spec's fields, for the effect option.
local EFFECT_KEYS = { "radius", "r", "g", "b", "noise", "duration", "fade",
  "grow", "live", "segments", "thickness", "ellipse", "rebuffer", "smoke",
  "depth", "preset", "owner", "seed", "random" }

-- Defaults are PX's own: radius (dmg + 2) * 2 (:33), hole = destroyRadius, and
-- the effect radius (dmg + 2) / 2 with integer division (custom_taze.c:314).
local function numbers(o)
  local damage = math.floor(o.damage or 0)
  local push = o.push or o.push_power or 0
  local radius = o.radius or (damage + 2) * 2
  local hole = o.hole or o.destroy_radius or damage
  local effect = o.effect_radius or math.floor((damage + 2) / 2)
  return damage, push, radius, hole, effect
end

-- Everything electrical_nearby can see, in WA's entity order. The engine caps
-- its query at 1000 px, so a larger blast falls back to the groups themselves.
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

-- effect = a px_effects burst spec (or false); it and the hole launch here.
function M.electric(o)
  o = o or {}
  local x, y = o.x, o.y
  if not x or not y then return 0 end
  local damage, push, radius, hole, effect_radius = numbers(o)
  local zap = o.zap or require("lib/electric_damage")
  local fx = o.fx or require("wf-lib/effects/px_effects")
  local hits = 0

  if damage > 0 and radius > 0 then
    local r2 = radius * radius
    for _, obj in ipairs(targets(x, y, radius)) do
      -- Mines are the chain arcs' business for now; graves are not PX
      -- explosion targets.
      if obj.kind ~= "mine" and obj.kind ~= "grave" then
        local dx, dy = obj.x - x, obj.y - y
        local d2 = dx * dx + dy * dy
        if d2 < r2 then
          local dist = math.sqrt(d2)
          local dmg = math.floor(damage * (radius - dist) / radius)  -- (:68-71)
          if dmg > 0 then
            local px, py = 0, 0
            if dist > 0.001 then
              local force = (dmg / 5) * (push / 100)  -- (:73-84)
              px, py = dx / dist * force, dy / dist * force
            end
            if obj.kind == "worm" then
              if o.taze ~= false then
                -- Land the damage first. The engine clears WA's static flag,
                -- so a lethal victim still gets the hold and its push.
                obj:hurt(dmg)
                zap.taze(obj, { frames = o.taze_frames or 20,
                  push_x = px, push_y = py })
              else
                obj:hurt{ amount = dmg, vx = px, vy = py }
              end
              hits = hits + 1
            elseif obj.kind == "crate" or obj.kind == "oil" then
              -- PX sends the same M_GUNEXP to every object (:103-124);
              -- object:hit is WA's damage and knockback path for a crate or
              -- oil drum.
              if obj:hit(dmg, px, py) then hits = hits + 1 end
            end
          end
        end
      end
    end
  end

  if o.destroy ~= false and hole > 0 and fx.crater then
    fx.crater{ x = x, y = y, radius = hole }  -- MakeHole (:136)
  end

  if o.chain ~= false and fx.arc then
    local cr = o.chain_radius or radius
    local cr2 = cr * cr
    for _, mine in ipairs(wa.mines.all()) do
      local dx, dy = mine.x - x, mine.y - y
      if dx * dx + dy * dy < cr2 then
        -- PX: linkedEffect2->SetTargetDynamic(centre, 2, 0.079, +-5) (:103).
        fx.arc{ from = { mine.x, mine.y }, to = { x, y },
          bulge = 5, speed = 0.079, terrain = false, owner = o.owner }
      end
    end
  end

  if o.effect ~= false and fx.burst then
    -- px_effects' burst keys, copied by a fixed list: pairs() would desync.
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
