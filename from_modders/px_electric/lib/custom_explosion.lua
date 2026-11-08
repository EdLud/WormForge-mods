-- PX's custom explosion, for electric weapons: damage, push, a taze, the hole
-- and the electric effect in one call. Ports do_custom_explosion
-- (wklua_and_px/utils/custom_explosion.c:17-295); the electric mine reaches it
-- through do_cus_exp_electric (custom_taze.c:308-324). It replaces WA's blast,
-- so the caller silences its own (a mine's `explosion.power = 0` is 0 damage
-- and 0 radius). PX applies the mine's damage twice (weapon_electric_mine.c:97
-- and :98); this applies it once.
--
-- Damage is PX's object walk (custom_explosion.c:46-125): M_GUNEXP to every
-- object in range. wa.world.blast is that walk, so worms, crates, oil drums,
-- mines, missiles, arrows and Lua actors whose `body.hit_by` takes blasts are
-- all hit. The taze pass then holds every worm in range, as TazeArtificial
-- does (:96-115); the hold drops the blast's own push and re-applies it on
-- release.

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
    -- A worm already at 0 HP is left out of the engine blast; remember it so
    -- the push below reaches it without hitting a worm the blast just killed.
    local zero = {}
    for _, w in ipairs(wa.worms.all()) do
      if w.hp <= 0 then zero[w.id] = true end
    end
    hits = wa.world.blast{ owner = o.owner, x = x, y = y, damage = damage,
      radius = math.ceil(radius), push_pct = push, kind = o.kind or "taze" }
    -- PX's taze pass (:96-115): the damage has landed, now hold every worm in
    -- range. The hold takes the worm, so the blast's push is dropped and put
    -- back on release with the same falloff push PX passes to TazeArtificial.
    local r2 = radius * radius
    for _, obj in ipairs(wa.worms.all()) do
      -- WA owns a dying/drowning/dead worm; no hold or push through its death.
      local live = not zap.can_affect or zap.can_affect(obj)
      if live then
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
            if o.taze ~= false then
              zap.taze(obj, { frames = o.taze_frames or 20,
                push_x = px, push_y = py })
            elseif zero[obj.id] then
              -- world.blast leaves a 0 HP worm out; PX's M_GUNEXP pushes it.
              obj:hurt{ amount = dmg, vx = px, vy = py }
              hits = hits + 1
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
