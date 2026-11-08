-- Shared Curse of Death state: PX's marks, curses, the homing pass and the
-- two overlays. Source: utility_curse_of_death/scripts/curse_of_death_script.txt.
--
-- Marked worms take 50% more damage. Cursed worms are the homing target of
-- every loose mine, missile, oil drum and arrow, wear PX's crosshair, and are
-- a magnet for magnetic actors (the Bowling Ball, both Bunker Busters).
-- `curse.install()` registers the shared hooks once, whichever of the four
-- weapons is placed.
local curse = {}

local CROSSHAIR = {
  "sprites/curse/crosshair1.png", "sprites/curse/crosshair2.png",
  "sprites/curse/crosshair3.png", "sprites/curse/crosshair4.png",
  "sprites/curse/crosshair5.png", "sprites/curse/crosshair6.png",
}
-- PX's marked-worm particle is WA sprite 616; WA has no glow, so the pack's
-- own glow sprite stands in for it.
local SMOKE = "sprites/glow.png"
-- sprites/glow.png carries its own alpha, so it is drawn with normal alpha.

-- PX lines 464-472 (ApplyCurse), 486-489 (Death Mark), 156-158 (speeds).
curse.MARK_TURNS = 4          -- markCoolDown, PX line 487
curse.MARK_MULTIPLIER = 1.5   -- dmgMultiplier, PX line 488 (default)
curse.CURSE_TURNS = 3         -- curseCoolDown, PX line 468
curse.MAX_LOCKS = 3           -- timesTargeted < 3, PX lines 301, 407 (default)
curse.RANGE = 149999          -- closestDistance, PX line 114
curse.BOX_FRONT = 28          -- DeathMarkFindTarget, PX lines 479-481
curse.BOX_HALF_Y = 15
curse.CLICK_HALF_X = 12       -- SCFindWorm, PX line 514
curse.CROSSHAIR_SCALE = 1.4   -- AddSpriteEx scale, PX line 409

-- Per worm id, so a freed worm's table cannot hold a stale handle.
local marked = {}   -- id -> { left }
local cursed = {}   -- id -> { left, phase, speed, reverse, rot, locks, ever }

local homing = {}   -- object key -> { iters, target, pass }
local ticker
local ensure_ticker
local start_thunder
local fx   -- the effects SDK, set in install; nil disables thunder
local installed = false

local function frame()
  return wa.world.frame() or 0
end

-- `damage` at `pct` percent, in whole numbers. PX truncates the new health
-- (line 159), so a part point of damage counts: 25 at 150% takes 38.
local function scaled(damage, pct)
  return (damage * pct + 99) // 100
end
-- The 0.9.8 blast fallback's own hurt, which the hook must not scale again.
local adding = false

-- WA keeps a 0 HP worm alive until its death starts, so only WA's death
-- states count (project rule: state, not HP or speed).
local function dead(w)
  if not w or not w.id then return true end
  local state = w.state
  return state == "dying" or state == "drowning" or state == "dead"
end

-- Find a live worm by id. Never keep a worm handle across frames: a dead
-- worm's object can be reused.
local function live_worm(id)
  for _, w in ipairs(wa.worms.all()) do
    if w.id == id and not dead(w) then return w end
  end
end

local function turn_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
  end
end

-- PX's curse steers native mines, missiles, oil drums and arrows. A Lua actor
-- that moves itself (the Bowling Ball, both Bunker Busters) reads magnetism
-- instead, so the curse becomes a magnet at the cursed worm and lets
-- wa.magnetism pull it: the actor's own movement does the homing. The field
-- is the Cursor's 300 px attract magnet. `native = false` keeps it off the
-- native objects the pass above already steers.
local MAGNET_RANGE = 300
local MAGNET_STRENGTH = 14000
local MAGNET_FORCE = 12
local MAGNET_SOFTENING = 10   -- attract softening (Electromagnet's)

local magnets = {}   -- worm id -> { actor, field }

local function stop_magnet(id)
  local m = magnets[id]
  if not m then return end
  magnets[id] = nil
  if m.field then pcall(function() m.field:remove() end) end
  if m.actor and not m.actor.dead then
    pcall(function() m.actor:despawn() end)
  end
end

local function start_magnet(w)
  if magnets[w.id] or not (wa.magnetism and wa.magnetism.field) then return end
  local id = w.id
  local ok, a = pcall(wa.actors.spawn, {
    sprite = false, x = w.x, y = w.y - 5, gravity = false, collide = false,
    solid = false, persist = true, drown = false, owner = w,
    on = function(actor)
      local v = live_worm(id)
      if not v or not cursed[id] then
        -- The field goes with its source.
        magnets[id] = nil
        actor:despawn()
        return
      end
      actor.x, actor.y = v.x, v.y - 5
      actor.vx, actor.vy = 0, 0
    end,
  })
  if not ok or not a then
    wa.log("curse magnet: " .. tostring(a))
    return
  end
  local made, field = pcall(wa.magnetism.field, {
    source = a, range = MAGNET_RANGE, strength = MAGNET_STRENGTH,
    max_force = MAGNET_FORCE, softening = MAGNET_SOFTENING,
    polarity = "attract", native = false,
  })
  if not made then
    a:despawn()
    wa.log("curse magnet: " .. tostring(field))
    return
  end
  magnets[id] = { actor = a, field = field }
end

local function play(w, id, flags)
  if w and not dead(w) then wa.sound.play(w, id, flags or 5) end
end

local function in_box(w, l, t, r, b)
  return w.x >= l and w.x <= r and w.y >= t and w.y <= b
end

-- The worm in front of `w`, if it is neither marked nor cursed. PX's
-- DeathMarkFindTarget, lines 432-447.
function curse.front(w)
  if not w then return nil end
  local side = w.facing
  if side ~= 1 and side ~= -1 then return nil end
  local l, r = w.x, w.x + curse.BOX_FRONT
  if side < 0 then l, r = w.x - curse.BOX_FRONT, w.x end
  local t, b = w.y - curse.BOX_HALF_Y, w.y + curse.BOX_HALF_Y
  for _, o in ipairs(wa.worms.all()) do
    if o.id ~= w.id and not dead(o) and not marked[o.id] and not cursed[o.id]
        and in_box(o, l, t, r, b) then
      return o
    end
  end
end

-- A worm at a clicked point. PX's SCFindWorm, lines 414-430: it may already
-- be marked or cursed.
function curse.at(w, x, y)
  if not w then return nil end
  local l, r = x - curse.CLICK_HALF_X, x + curse.CLICK_HALF_X
  local t, b = y - curse.BOX_HALF_Y, y + curse.BOX_HALF_Y
  for _, o in ipairs(wa.worms.all()) do
    if o.id ~= w.id and not dead(o) and in_box(o, l, t, r, b) then
      return o
    end
  end
end

-- The multiplier is the marking weapon's option, stored on the mark so two
-- placed mark weapons keep their own numbers (PX's dmgMultiplier is per worm).
function curse.mark(w, mult)
  if dead(w) then return false end
  mult = mult or curse.MARK_MULTIPLIER
  marked[w.id] = { left = curse.MARK_TURNS, mult = mult, pct = math.floor(mult * 100 + 0.5) }
  play(w, 31)
  play(w, 138)
  start_thunder(w, mult)
  return true
end

-- Thunder on a marked worm: the effects SDK's "thunder" preset (its reach
-- bolts, coming down from the sky onto the emitter). The emitter follows the
-- worm and ends itself when the mark is gone or the worm dies (its follow
-- returns nothing). Only its seed is chosen here, from a generator of its own,
-- so marking never consumes the game's random numbers.
local thunder = {}
local sim_seed = 91731

local function srand()
  sim_seed = (sim_seed * 16807) % 2147483647
  return sim_seed / 2147483647
end

start_thunder = function(w, mult)
  if not fx or not w then return end
  local id = w.id
  local old = thunder[id]
  if old and not old.dead then old:remove() end
  local bolt_r, bolt_g, bolt_b = 215, 190, 255 -- Default lavender
  if (mult or curse.MARK_MULTIPLIER) >= 2.0 then
    bolt_r, bolt_g, bolt_b = 255, 30, 50     -- Red
  end  
  local ok, e = pcall(fx.emitter, {
    preset = "thunder", owner = w, x = w.x, y = w.y - 21, trail = false,
    reach = { r = bolt_r, g = bolt_g, b = bolt_b },
    seed = 1 + math.floor(srand() * 2000000000),
    follow = function()
      if not marked[id] then return nil end
      local v = live_worm(id)
      if not v then return nil end
      return v.x, v.y - 21, v.vx, v.vy
    end,
  })
  if not ok then
    wa.log("curse thunder: " .. tostring(e))
    fx = nil
    return
  end
  thunder[id] = e
end

ensure_ticker = function()
  local function advance(c, f)
    local cspd = math.floor(c.speed / 3)
    c.phase = c.phase + 0.001 * 6.0 * cspd
    if not c.reverse then
      if f % 3 == 0 then c.speed = c.speed + 1 end
    else
      c.rot = c.rot + 0.02 + c.speed / 120
      if f % 2 == 0 then c.speed = c.speed - 1 end
    end
    if c.speed > 15.01 then
      c.reverse = true
      c.speed = 15
    end
    if c.speed < 5.01 then
      c.reverse = false
      c.speed = 6
    end
    if c.phase > 1 then c.phase = 0 end
    c.rot = c.rot % (2 * math.pi)
  end

  ticker = wa.actors.spawn({
    sprite = false, x = 0, y = 0, gravity = false, collide = false,
    persist = true, drown = false,
    on = function(a)
      a.vx, a.vy = 0, 0
      local f, any = frame(), false
      for _, id in ipairs(wa.sorted(cursed)) do
        local c = cursed[id]
        if live_worm(id) then
          any = true
          advance(c, f)
        else
          cursed[id] = nil
          stop_magnet(id)
        end
      end
      if not any then
        ticker = nil
        a:despawn()
      end
    end,
  })
end

function curse.curse(w, cap)
  if dead(w) then return false end
  cursed[w.id] = {
    left = curse.CURSE_TURNS, phase = 0, speed = 5.0, reverse = false,
    rot = 0, locks = 0, ever = {}, cap = cap or curse.MAX_LOCKS,
  }
  play(w, 31)
  play(w, 138)
  if not ticker then ensure_ticker() end
  start_magnet(w)
  return true
end

function curse.nothing_found(w)
  wa.hud.message_top("Nothing found!")
  play(w, 120, 3)
end

-- PX line 100-102: missiles dominate the cooldown, then the object count.
local cache_frame, cache_cooldown = -1, 2
local function cooldown()
  local f = frame()
  if f == cache_frame then return cache_cooldown end
  local missiles = #wa.missiles.all()
  local n
  if missiles > 50 then
    n = math.floor(missiles * 0.15)
  else
    local objects = #wa.worms.all() + missiles + #wa.mines.all()
      + #wa.oil.all() + #wa.arrows.all() + #wa.crates.all()
    n = objects > 120 and math.floor(objects * 0.09) or 2
  end
  if n < 1 then n = 1 end
  cache_frame, cache_cooldown = f, n
  return n
end

local function current_pass()
  return math.floor(frame() / cooldown())
end

-- The closest cursed worm the object can see. `key` lets an object that
-- already locked a worm keep it after that worm has spent its three locks
-- (PX's CheckTargetArray returns true for an existing targeter, line 178).
local function choose_target(key, x, y, skip_id)
  local best, best_d2
  for _, id in ipairs(wa.sorted(cursed)) do
    local c = cursed[id]
    if id ~= skip_id and (c.ever[key] or c.locks < (c.cap or curse.MAX_LOCKS)) then
      local w = live_worm(id)
      if w then
        local dx, dy = w.x - x, w.y - y
        local d2 = dx * dx + dy * dy
        if d2 < curse.RANGE * curse.RANGE and (not best_d2 or d2 < best_d2) then
          local hit = wa.land.trace(x, y, w.x, w.y)
          if not (hit and hit.hit) then
            best, best_d2 = id, d2
          end
        end
      end
    end
  end
  return best
end

-- Re-target at most once per cooldown window and count the lock, as PX's
-- AssignCurseHomingTargets/CheckTargetArray do. PX steers only from that
-- frame, so between windows the object keeps whatever velocity it has; the
-- second return says whether this frame is a window.
local function target_for(key, x, y, skip_id, cap)
  local h = homing[key]
  if not h then
    h = { iters = 0 }
    homing[key] = h
  end
  local p = current_pass()
  if h.pass == p then return h, false end
  h.pass = p
  h.target = nil
  if cap and h.iters >= cap then return h, true end
  local target = choose_target(key, x, y, skip_id)
  if target then
    h.target = target
    h.iters = h.iters + 1
    local c = cursed[target]
    if not c.ever[key] then
      c.ever[key] = true
      c.locks = c.locks + 1
    end
  end
  return h, true
end

-- PX's homeToPlace (utils_red/scripts/missile_weap_utils.txt, lines 122-145).
local function steer(x, y, vx, vy, tox, toy, speed, turn)
  local dx, dy = tox - x, toy - y
  local d = math.sqrt(dx * dx + dy * dy)
  if d > 0 then
    dx, dy = dx / d, dy / d
  end
  return vx + (dx * speed - vx) * turn,
    vy + (dy * speed - vy) * turn
end

-- ChaseTargetCurse, lines 151-164.
local HOMING = {
  missile = { speed = 24.0, turn = 0.09, cap = 90 },
  mine = { speed = 13.0, turn = 0.12, cap = 67 },
  oil = { speed = 9.0, turn = 0.10, cap = 69 },
  arrow = { speed = 12.5, turn = 0.25, cap = false },
}

local function chase(key, kind, x, y, vx, vy, skip_id)
  local spec = HOMING[kind]
  local h, due = target_for(key, x, y, skip_id, spec.cap)
  if not due or not h.target then return end
  local w = live_worm(h.target)
  if not w then return end
  return steer(x, y, vx, vy, w.x, w.y - 5, spec.speed, spec.turn)
end

-- A failed draw call is logged once instead of failing silently every frame.
local draw_failed = false
local function safe_quad(args)
  local ok, err = pcall(wa.draw.quad, args)
  if not ok and not draw_failed then
    draw_failed = true
    wa.log("curse draw failed: " .. tostring(err))
  end
end

-- Corners are { x =, y = } tables, as the engine's own saw draw passes them.
local function draw_quad(sprite, cx, cy, size, colour, depth, blend, rot)
  local h = size / 2
  local c, sn = 1, 0
  if rot and rot ~= 0 then c, sn = math.cos(rot), math.sin(rot) end
  local function corner(dx, dy)
    return { x = cx + dx * c - dy * sn, y = cy + dx * sn + dy * c }
  end
  safe_quad({
    points = { corner(-h, -h), corner(h, -h), corner(h, h), corner(-h, h) },
    sprite = sprite, frame = 0, color = colour, depth = depth,
    blend = blend or "alpha",
  })
end

local function argb(a, r, g, b)
  return a * 0x1000000 + r * 0x10000 + g * 0x100 + b
end

local function draw_crosshair(cx, cy, size, rot, sprite)
  local h = size / 2
  local c, s = wa.math.cos(rot), wa.math.sin(rot)
  local function point(dx, dy)
    return { x = cx + dx * c - dy * s, y = cy + dx * s + dy * c }
  end
  safe_quad({
    points = { point(-h, -h), point(h, -h), point(h, h), point(-h, h) },
    sprite = sprite, frame = 0, color = 0xFFFFFFFF, depth = wa.depth.FRONT,
    blend = "alpha",
  })
end

-- Marked-worm smoke: PX spawns three particles per worm per frame (sprite
-- 616, 50 frames of life, random slow drift, drag, a little gravity, size
-- 0.5 -> 0, colour 80 -> 0). This is a small pool of the same, stepped once
-- per simulation frame and drawn each rendered frame. It is presentation
-- only, so it has its own random numbers and never touches the simulation.
local SMOKE_LIFE = 25
local SMOKE_PER_FRAME = 2
local SMOKE_MAX = 400          -- safety cap on live particles
local SMOKE_BASE = 32          -- px size of the sprite at scale 1.0
local SMOKE_SIZE0, SMOKE_SIZE1 = 0.5, 0.0
local SMOKE_COLOUR0, SMOKE_COLOUR1 = 80, 0
-- PX has start alpha 1 and end alpha 100. Read as percent, the oldest and
-- smallest puffs were the most opaque and the trail ended in a solid spike,
-- so it fades OUT here instead.
local SMOKE_ALPHA0, SMOKE_ALPHA1 = 60, 0
local SMOKE_SPEED_MIN, SMOKE_SPEED_MAX = 0.2, 0.9
local SMOKE_CONE = 0.5         -- radians either side of straight up
local SMOKE_DRAG = 0.96        -- PX air resistance 0.50 (per-frame factor)
local SMOKE_WOBBLE = 0.04      -- sideways wander only
local SMOKE_RISE = 0.015        -- steady lift per frame: dissipating cloud
local SMOKE_SCALE_MIN, SMOKE_SCALE_MAX = 0.70, 1.30   -- per-puff size variety
local SMOKE_SPIN = 0.03        -- radians per frame, either way
local particles = {}
local last_smoke_frame

-- Looks only, so a small generator of its own: wa.draw.random's arguments and
-- range are not documented, and a result that does not spread made every puff
-- drift the same way (a spike). Park-Miller, safe in double precision.
local smoke_seed = 48271
local function rnd(a, b)
  smoke_seed = (smoke_seed * 16807) % 2147483647
  return a + (b - a) * (smoke_seed / 2147483647)
end

local function step_smoke(f)
  if last_smoke_frame == nil or f < last_smoke_frame then
    -- First frame, a new match or a replay rewind: start clean.
    last_smoke_frame = f
    particles = {}
    return
  end
  local steps = f - last_smoke_frame
  if steps <= 0 then return end
  if steps > 3 then steps = 3 end   -- no burst after a pause or a stall
  last_smoke_frame = f
  for _ = 1, steps do
    for i = #particles, 1, -1 do
      local q = particles[i]
      q.age = q.age + 1
      if q.age >= SMOKE_LIFE then
        table.remove(particles, i)
      else
        q.vx = (q.vx + rnd(-1, 1) * SMOKE_WOBBLE) * SMOKE_DRAG
        q.vy = (q.vy - SMOKE_RISE) * SMOKE_DRAG
        q.x, q.y = q.x + q.vx, q.y + q.vy
      end
    end
    for _, id in ipairs(wa.sorted(marked)) do
      local w = live_worm(id)
      if w then
        for _ = 1, SMOKE_PER_FRAME do
          if #particles >= SMOKE_MAX then break end
          local angle = -math.pi / 2 + rnd(-SMOKE_CONE, SMOKE_CONE)   -- up, in a cone
          local speed = rnd(SMOKE_SPEED_MIN, SMOKE_SPEED_MAX)
          particles[#particles + 1] = {
            x = w.x + rnd(-5, 5), y = w.y - 20,
            vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
            age = 0, scale = rnd(SMOKE_SCALE_MIN, SMOKE_SCALE_MAX),
            rot = rnd(0, 2 * math.pi), spin = rnd(-SMOKE_SPIN, SMOKE_SPIN),
          }
        end
      end
    end
  end
end

function curse.install()
  if installed then return end
  installed = true

  -- Thunder is the effects SDK's "thunder" preset. Without the SDK the rest
  -- still works. fx.install is shared: it is called the way the electric mine
  -- calls it, so whichever bundle installs first leaves the trail on.
  local ok_fx, lib = pcall(require, "wf-lib/effects/px_effects")
  local ok_tr, tr = pcall(require, "wf-lib/effects/trail")
  if ok_fx and ok_tr and lib.PRESETS and lib.PRESETS.thunder then
    local ok, err = pcall(function()
      lib.install{ trail = true }
      wa.assets.load{ sprites = { tr.BEAM, tr.GLOW } }
    end)
    if ok then
      fx = lib
      wa.log("curse thunder: ready")
    else
      wa.log("curse thunder setup: " .. tostring(err))
    end
  else
    wa.log("curse thunder: effects SDK with a thunder preset not found")
  end

  -- The crosshair art must be registered at install, or the draw call has no
  -- sprite to use. (Harmless if a weapon's own install already loads it.)
  local ok, err = pcall(wa.assets.load, {
    sprites = { table.unpack(CROSSHAIR) },
    gpu_prefix = "sprites/curse/",
  })
  if not ok then wa.log("curse assets: " .. tostring(err)) end
  ok, err = pcall(wa.assets.load, { sprites = { SMOKE }, gpu_prefix = "sprites/" })
  if not ok then wa.log("curse glow asset: " .. tostring(err)) end

  -- A marked worm takes its mark's percentage of every blast and hit (PX's
  -- M_EXPLOSION and M_GUNEXP, lines 154-173), flames and the axe's share
  -- too. Scaled in `pre`, so WA takes it as its own damage: one number, the
  -- hit's own push, and WA's death for a worm it brings to 0. A blast's
  -- `damage` is what it takes off this worm; its `amount` is its power, and
  -- scaling that would also scale the blast's reach and push.
  wa.on.hurt(function(hit)
    local w = hit.worm
    if not w or adding then return end
    local m = marked[w.id]
    if not m then return end
    local kind = hit.kind
    if hit.phase == "pre" then
      if hit.expected == 0 then return end   -- WA takes nothing (Phased Worms, a lockout)
      if kind == "blast" then
        -- hit.damage can be set only on DLLs after 0.9.8, which also give
        -- hit.expected; older ones get the post fallback below.
        if hit.expected ~= nil then hit.damage = scaled(hit.damage, m.pct) end
      elseif kind == "percent" then
        hit.amount = math.min(100, scaled(hit.amount, m.pct))
      elseif kind ~= "poison" and kind ~= "nonlethal" then
        -- Every other kind is a hit (0x4B): its amount is the damage. The
        -- engine names WA's kinds, so this is what catches "bullet", "fire",
        -- "arrow", the scripted "taze" and a bundle's own kind.
        hit.amount = scaled(hit.amount, m.pct)
      end
    elseif kind == "blast" and hit.expected == nil and hit.lost > 0 then
      -- 0.9.8: the blast's extra share as damage alone, no second hit.
      adding = true
      w:hurt{ amount = scaled(hit.lost, m.pct) - hit.lost, react = false }
      adding = false
    end
  end)

  -- PX counts a marked/cursed worm's turns on the turns of its own team
  -- (lines 362-383) and zeroes every homing counter at PreTurnStart (206).
  wa.on.turn_start(function(ev)
    local w = ev.worm
    if not w then return end
    homing = {}
    -- A magnet belongs to a live curse; drop any whose curse ended early.
    for _, id in ipairs(wa.sorted(magnets)) do
      if not cursed[id] then stop_magnet(id) end
    end
    local team = w.team
    for _, id in ipairs(wa.sorted(marked)) do
      local m = marked[id]
      local victim = live_worm(id)
      if victim and victim.team == team then
        m.left = m.left - 1
        if m.left <= 0 then marked[id] = nil end
      end
    end
    for _, id in ipairs(wa.sorted(cursed)) do
      local c = cursed[id]
      local victim = live_worm(id)
      if victim and victim.team == team then
        local keep = c.locks < 2
        if keep then
          c.left = c.left - 1
          keep = c.left > 0
        end
        if not keep then
          cursed[id] = nil
          stop_magnet(id)
        end
      end
    end
  end)

  wa.on.death(function(ev)
    local v = ev.victim
    if not v then return end
    marked[v.id] = nil
    cursed[v.id] = nil
    stop_magnet(v.id)
  end)

  -- Every missile, including the shooter's own. The engine reads vx/vy back
  -- from this table, so write the table, never a missile handle.
  wa.on.missile_frame(function(m)
    if m.phase ~= "post" or frame() < 50 then return end
    if m.y > wa.world.water() then return end
    local w = turn_worm()
    local vx, vy = chase("m:" .. m.id, "missile", m.x, m.y, m.vx, m.vy, w and w.id)
    if vx then
      m.vx, m.vy = vx, vy
    end
  end)

  -- Mines, oil drums and arrows: before WA's own body step, so the new
  -- velocity is what the body moves with. `warp` clears WA's settled latch;
  -- without it a settled mine ignores the velocity (a deliberate workaround:
  -- PX writes SpX/SpY directly into the C++ object).
  wa.on.body_move(function(b)
    local kind = b.kind
    if not HOMING[kind] or frame() < 50 then return end
    if b.y > wa.world.water() then return end
    local w = turn_worm()
    local vx, vy = chase("b:" .. b.uid, kind, b.x, b.y, b.vx, b.vy, w and w.id)
    if vx then
      b:warp({ x = b.x, y = b.y, vx = vx, vy = vy })
    end
  end, { kinds = { "mine", "oil", "arrow" } })

  wa.on.draw(function()
    local f = frame()
    for _, id in ipairs(wa.sorted(cursed)) do
      local c = cursed[id]
      local w = live_worm(id)
      if w and c.locks < (c.cap or curse.MAX_LOCKS) then
        local n = math.floor(c.phase * 6) + 1
        if n > 6 then n = 6 elseif n < 1 then n = 1 end
        local size = 32 * curse.CROSSHAIR_SCALE
        draw_crosshair(w.x, w.y, size, c.rot, CROSSHAIR[n])
      end
    end
    -- PX lines 336-358: the marked worm's smoke, as real particles.
    step_smoke(f)
    for _, q in ipairs(particles) do
      local t = q.age / SMOKE_LIFE
      local size = SMOKE_BASE * q.scale * (SMOKE_SIZE0 + (SMOKE_SIZE1 - SMOKE_SIZE0) * t)
      if size > 0.5 then
        local c = math.floor(SMOKE_COLOUR0 + (SMOKE_COLOUR1 - SMOKE_COLOUR0) * t)
        local alpha = (SMOKE_ALPHA0 + (SMOKE_ALPHA1 - SMOKE_ALPHA0) * t) / 100
        draw_quad(SMOKE, q.x, q.y, size,
          argb(math.floor(255 * alpha), c, c, c), wa.depth.EFFECTS, nil,
          q.rot + q.spin * q.age)
      end
    end
  end)
end

-- The same check pyro.lua uses: a component in no panel slot registers
-- nothing, and a profile may place only some of the four weapons.
function curse.placed(ctx)
  local informed = false
  if type(ctx.weapons) == "table" then
    informed = true
    if ctx.weapons[ctx.id] ~= nil then return true end
  end
  if type(ctx.placed) == "table" then
    informed = true
    for _, weapon in ipairs(ctx.placed) do
      if weapon == ctx.id or (type(weapon) == "table" and weapon.id == ctx.id) then
        return true
      end
    end
  end
  return not informed
end

-- Harness hook: the shared state, without the engine.
curse._state = function()
  return marked, cursed, homing
end

return curse
