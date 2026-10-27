-- Project X's CSaw (PX_pending/map_object_saw/scripts/saw_script.txt).
--
-- A saw is stationary and invincible: PX resets PosX/PosY and SpX/SpY every
-- frame, ignores explosions while isDestructible is false, and never calls
-- Free. The port therefore uses one controller actor per saw, hidden behind a
-- small mask disc, and draws the three art layers itself. Collision is a Lua
-- circle (radius 100*size); the disc is a little smaller, because actor body
-- and mask sprites do not scale with a:gfx{scale}.
--
-- The source numbers and line references are in report_saw.md. No terrain
-- cut/dig is done on spawn: a saw may sit embedded or behind terrain.

local M = {}

local SHEET = "sprites/saw/sawsheet.png"
local BLADE = "sprites/saw/foldedblades.png"

-- Engine mask actors use the sprite's pixel size; a:gfx{scale} only changes
-- the picture. Pick the largest disc that still fits inside the Lua circle.
local MASKS = {
  { r = 8,  path = "sprites/saw/mask_08.png" },
  { r = 16, path = "sprites/saw/mask_16.png" },
  { r = 24, path = "sprites/saw/mask_24.png" },
  { r = 32, path = "sprites/saw/mask_32.png" },
  { r = 40, path = "sprites/saw/mask_40.png" },
  { r = 48, path = "sprites/saw/mask_48.png" },
  { r = 56, path = "sprites/saw/mask_56.png" },
  { r = 64, path = "sprites/saw/mask_64.png" },
  { r = 72, path = "sprites/saw/mask_72.png" },
  { r = 80, path = "sprites/saw/mask_80.png" },
  { r = 88, path = "sprites/saw/mask_88.png" },
  { r = 96, path = "sprites/saw/mask_96.png" },
}
local MASK_SPRITES = {}
for i = 1, #MASKS do MASK_SPRITES[i] = MASKS[i].path end

local function mask_for(radius)
  local best = MASKS[1].path
  for i = 1, #MASKS do
    if MASKS[i].r <= radius - 1 then best = MASKS[i].path end
  end
  return best
end
local CUT = {
  "sounds/saw/saw_cut_1.wav",
  "sounds/saw/saw_cut_2.wav",
  "sounds/saw/saw_cut_3.wav",
  "sounds/saw/saw_cut_4.wav",
}
local CLANK = "sounds/saw/clank-sound.wav"
local SHOCK = "sounds/saw/electric-shock.wav"

local TWO_PI = 2 * 3.141592653589793

-- PX uses the visible worm colour (GetTeamColor), not the team identity.
local TEAM_COLOUR = {
  [0] = 0xFFFF6060, -- red
  [1] = 0xFF6080FF, -- blue
  [2] = 0xFF60FF60, -- green
  [3] = 0xFFFFFF60, -- yellow
  [4] = 0xFFD060FF, -- purple
  [5] = 0xFF60FFFF, -- cyan
}

local current_turn_worm = nil 

local WORM_RADIUS = 7
local OBJECT_RADIUS = { mine = 6, crate = 10, oil = 12 }
local MISSILE_RADIUS = 4
-- Frames a missile may sit inside the Lua check circle before the fallback
-- shove. A real mask bounce leaves in one or two frames.
local MISSILE_FRAMES = 4

local installed = false
local fx, electric, taze_mine
local saws = {}
local turn_active = false

-- PX stores timesSliced/hitFrame on the worm and sawhitlimit/hitFrame on the
-- object, so every saw shares them. Keep the same maps module-wide.
local worm_slices, worm_next, worm_taze = {}, {}, {}
local obj_hits, obj_next = {}, {}

-- The saw keeps its own static-corpse guard. The electric hold is now
-- unguarded on purpose; the engine clears WA's static flag.
local function can_affect(w)
  if not w then return false end
  local hp = w.hp
  if hp == nil or hp > 0 then return true end
  return math.abs(w.vx or 0) > 0.01 or math.abs(w.vy or 0) > 0.01
end

local function frame()
  return wa.world.frame() or 0
end

-- The turn's worm.
local function current_worm()
  --for _, w in ipairs(wa.worms.all()) do
  --  if w and w.turn then return w end
  --end
  return current_turn_worm
end

-- Any live worm can lend the mask actor its collision helper. PX's saw belongs
-- to the map, not to the worm that fired it: using the shooter meant the actor
-- outlived (or was freed with) a worm that may leave the round later.
local function fetchWorm()
  for _, w in ipairs(wa.worms.all()) do
    if w and w.kind == "worm" then return w end
  end
end

-- Whose saw it is. An explosion's `ev.worm` is the missile's owner, which need
-- not be a worm (see the Javelin in rules.lua), and then it has no real
-- alliance: reading it gave every saw team 0, the first colour, so the saw
-- just made it return current turn since missile obj can't persist past a turn
local function shooter_of(ev)
  return current_worm()
end

local function play(s, path)
  if s.controller and path then wa.sound.play(s.controller, path) end
end

local function spark(x, y, r, g, b, owner)
  if not fx then return end
  local s = fx.spark{ x = x, y = y, cell = 20, frames = 1, size = 0.5,
    rate = 1, pause = 0, r = r, g = g, b = b, owner = owner }
  -- fx.spark has no `life` in its key list; without one it never leaves the
  -- draw list. This is a one-shot blood/spark, not a persistent emitter.
  if s then s.life = 1 end
end

local function reset_turn(s)
  s.hits_this_turn = 0
  s.stop_rotation = false
  s.missile_frames = {}
end

local function knockback(s, target, factor, is_worm)
  local dx = (target.x or 0) - s.x
  local dy = (target.y or 0) - s.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 0.1 then dist = 0.1 end
  local nx, ny = dx / dist, dy / dist

  local vx, vy = target.vx or 0, target.vy or 0
  local speed = math.sqrt(vx * vx + vy * vy)

  local f = factor
  if s.electric then f = f + f * 0.77 end
  local base = 1.5 + f * 1.5
  if s.electric then base = base * 2 end
  local bounce = base + speed * 0.75
  local dot = vx * nx + vy * ny
  if dot > 0 then bounce = bounce * 0.5 end

  local tx, ty = vx - dot * nx, vy - dot * ny
  local out_x = nx * bounce + tx * 0.8
  local out_y = ny * bounce + ty * 0.8
  local lower = s.electric and 7.0 or 4.0
  local max = (is_worm and 13.9 or 17.0) + (s.electric and 5.5 or 0)
  local total = math.sqrt(out_x * out_x + out_y * out_y)

  if total < lower and total > 0.01 then
    out_x = (out_x / total) * lower
    out_y = (out_y / total) * lower
  elseif total <= 0.01 then
    out_x, out_y = nx * lower, ny * lower
  end
  total = math.sqrt(out_x * out_x + out_y * out_y)
  if total > max then
    out_x = (out_x / total) * max
    out_y = (out_y / total) * max
  end

  local limit = s.electric and 42 or 33
  local dmg = math.floor(speed * 2.25 + factor * 4.0)
  if dmg > limit then dmg = limit end
  if dmg < 15 then dmg = 15 end
  if s.electric then dmg = dmg * 1.5 end

  -- PX's visual kick, opposite the normal spin.
  s.angle = s.angle + s.rotation * 3.0
  s.stop_rotation = false
  return dmg, out_x, out_y
end

local function hit_worm(s, w, now)
  if not can_affect(w) then return end
  local id = w.id
  if now < (worm_next[id] or 0) or now < (worm_taze[id] or 0) then
    return
  end
  local slice = (worm_slices[id] or 0) + 1
  if slice > 26 then return end
  worm_slices[id] = slice
  worm_next[id] = now + 7

  local dmg, out_x, out_y
  if slice <= 19 then
    dmg, out_x, out_y = knockback(s, w, 0.77, true)
    s.times_collided = s.times_collided + 1
    play(s, CUT[wa.random(1, 4)])
    if w.state == "frozen" or w.drilling then
      play(s, CLANK)
      spark(w.x, w.y, 255, 255, 255, s.controller)
    else
      spark(w.x, w.y, 190, 20, 20, s.controller)
    end
  else
    -- CSawCollission only calls ApplySawKnockback for the first 19 slices;
    -- later slices keep the initial damage value of 15.
    dmg = 15
    if w.state == "frozen" or w.drilling then
      -- The clank/particle branch in processSawCollission runs after the
      -- first-19 sound gate, so it also runs on later slices.
      play(s, CLANK)
      spark(w.x, w.y, 255, 255, 255, s.controller)
    else
      spark(w.x, w.y, 190, 20, 20, s.controller)
    end
  end

  if slice <= 19 and s.electric then
    local frames = math.floor(dmg * 1.15)
    if electric then
      electric.hurt_electric(w, math.floor(dmg), {
        frames = frames, push_x = out_x, push_y = out_y,
        damage_now = true,
      })
      worm_taze[id] = now + frames + 7
    else
      w.vx, w.vy = out_x, out_y
      w:hurt(math.floor(dmg))
    end
  elseif s.electric then
    -- After slice 19 there is no taze or knockback, but PX still damages a
    -- frozen/drilling worm when the saw is supercharged.
    w:hurt(math.floor(dmg))
  elseif w.state ~= "frozen" and w.state ~= "drilling" then
    if out_x then w.vx, w.vy = out_x, out_y end
    w:hurt(math.floor(dmg))
  elseif out_x then
    -- Frozen/drilling worms are pushed but not damaged by a normal saw.
    w.vx, w.vy = out_x, out_y
  end
end

local function object_hit(s, obj, kind, damage, factor, cooldown, now)
  local id = obj.id
  local count = obj_hits[id] or 0
  if kind == "crate" then
    count = count + 1
    obj_hits[id] = count
    if count > 5 then return end
    if not turn_active then
      -- PX pushes crates outside turns but does not break them.
      play(s, CLANK)
      local _, fx_, fy_ = knockback(s, obj, factor, false)
      obj.vx, obj.vy = fx_, fy_
      return
    end
  elseif kind == "mine" then
    if count >= 20 or now < (obj_next[id] or 0) then return end
    obj_hits[id] = count + 1
    -- PX calls TazeMine before the mine's own hit message. Mark it first:
    -- obj:hit can free the mine, and then its id/uid can no longer be read.
    if s.electric and taze_mine then
      taze_mine.taze(obj, { owner = s.controller })
    end
  else
    obj_hits[id] = count + 1
  end

  s.hits_this_turn = s.hits_this_turn + 1
  obj_next[id] = now + (cooldown or 1)
  local ox, oy = obj.x, obj.y
  local _, fx_, fy_ = knockback(s, obj, factor, false)
  -- Set the push before hit: WorldHandle has no liveness test, and `hit` may
  -- free a mine/oil drum, so reading `obj.kind` afterwards is unsafe.
  obj.vx, obj.vy = fx_, fy_
  obj:hit(damage, 0, 0, kind == "crate" and "projectile" or nil)
  if kind == "crate" or kind == "mine" then play(s, CLANK) end
  spark(ox, oy, 255, 255, 255, s.controller)
end

local function missile_push(s, m, now)
  local id = m.id
  local count = obj_hits[id] or 0
  if count >= 20 or now < (obj_next[id] or 0) then return end
  obj_hits[id] = count + 1
  s.hits_this_turn = s.hits_this_turn + 1
  obj_next[id] = now + 5
  local _, fx_, fy_ = knockback(s, m, 0.88, false)
  -- The engine mask handles a normal bounce. This is the fallback for a
  -- missile that stayed inside the check circle for MISSILE_FRAMES frames.
  m.vx = (m.vx or 0) + fx_
  m.vy = (m.vy or 0) + fy_
  play(s, CLANK)
  spark(m.x, m.y, 255, 255, 255, s.controller)
end

local function process(s, now)
  -- PX clears stopRotation before processSawCollission (:186-189), so the
  -- anti-loop return below cannot leave an ally-contact stop latched.
  s.stop_rotation = false
  if s.hits_this_turn > 88 then return end

  for _, w in ipairs(wa.worms.all()) do
    local dx, dy = w.x - s.x, w.y - s.y
    local reach = s.radius + WORM_RADIUS
    if dx * dx + dy * dy <= reach * reach then
      if s.team ~= nil and s.team >= 0 and w.alliance == s.team then
        s.stop_rotation = true
      else
        hit_worm(s, w, now)
      end
    end
  end

  local function objects(list, kind, radius, damage, factor, cooldown)
    for _, obj in ipairs(list) do
      local dx, dy = obj.x - s.x, obj.y - s.y
      local reach = s.radius + radius
      if dx * dx + dy * dy <= reach * reach then
        object_hit(s, obj, kind, damage, factor, cooldown, now)
      end
    end
  end
  objects(wa.crates.all(), "crate", OBJECT_RADIUS.crate, 5, 0.77, 1)
  objects(wa.mines.all(), "mine", OBJECT_RADIUS.mine, 15, 0.85, 5)
  objects(wa.oil.all(), "oil", OBJECT_RADIUS.oil, 20, 0.87, 1)

  local frames = {}
  for _, m in ipairs(wa.missiles.all()) do
    local dx, dy = m.x - s.x, m.y - s.y
    local reach = s.radius + MISSILE_RADIUS
    if dx * dx + dy * dy <= reach * reach then
      local n = (s.missile_frames[m.id] or 0) + 1
      if n > MISSILE_FRAMES then
        n = 0
        missile_push(s, m, now)
      end
      frames[m.id] = n
    end
  end
  s.missile_frames = frames
end

local function tick(a, s)
  -- PX resets PosX/PosY and SpX/SpY every frame (:171-175). A blast still
  -- lands on the visible mask actor, and WA frees a visible actor that leaves
  -- the map, so pin the controller before anything else runs.
  a.x, a.y = s.x, s.y
  a.vx, a.vy = 0, 0

  local now = frame()
  process(s, now)

  if s.hits_this_turn < 88 and not s.stop_rotation then
    s.angle = (s.angle - s.rotation) % TWO_PI
  end
  if s.times_collided >= 8 and not s.transition then
    s.rotation = s.rotation - 0.05
    s.transition = true
  end
end

local function spawn_controller(s)
  local a = wa.actors.spawn{
    owner = fetchWorm() or current_worm(),
    sprite = mask_for(s.radius), x = s.x, y = s.y,
    kind = "saw", mask = true,
    -- The mask must stay exactly where the saw is drawn. Mask land/actor
    -- resolution would shove the disc, and the object layer is where WA keeps
    -- a persistent map object (PX's saw is in the oil-drum layer).
    mask_land = false, mask_actors = false, as_object = true,
    gravity = false, collide = false, drown = false, persist = true,
    on = function(actor) tick(actor, s) end,
  }
  if not a then return nil end
  a:gfx{ blend = "add", tint = 0, depth = s.depth }
  return a
end

local QUAD = { blend = "alpha", points = { {}, {}, {}, {} } }
local function draw_layer(s, sheet, frame, depth, colour, angle)
  local half = 110 * s.size
  local c = wa.math.cos(angle)
  local sn = wa.math.sin(angle)
  local p = QUAD.points
  local corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }
  for i = 1, 4 do
    local ox, oy = corners[i][1] * half, corners[i][2] * half
    p[i].x = s.x + ox * c - oy * sn
    p[i].y = s.y + ox * sn + oy * c
  end
  QUAD.sprite, QUAD.frame, QUAD.depth, QUAD.color = sheet, frame, depth, colour
  wa.draw.quad(QUAD)
end

local function draw()
  for _, s in ipairs(saws) do
    local tc = s.times_collided
    -- Source Draw: `if (tc <= 14) SawIn; else if (tc >= 14) SawInBlood`
    -- means the inner blood frame starts at 15, not 14.
    local inner = s.electric and 8 or (tc > 14 and 4 or 3)
    local outer
    if s.electric then
      outer = tc >= 14 and 7 or (tc >= 7 and 6 or 5)
    else
      outer = tc >= 14 and 2 or (tc >= 7 and 1 or 0)
    end
    local depth = s.depth
    draw_layer(s, SHEET, inner, depth, 0xFFFFFFFF, 0)
    draw_layer(s, SHEET, outer, depth + 1, 0xFFFFFFFF, s.angle)
    local colour = s.team ~= nil and TEAM_COLOUR[s.team] or nil
    if colour and (tc < 7 or tc >= 8) then
      local outline = tc < 7 and 9 or 10
      draw_layer(s, SHEET, outline, depth + 2, colour, s.angle)
    end
  end
end

function M.install()
  if installed then return end
  installed = true
  fx = require("wf-lib/effects/px_effects")
  local trail = require("wf-lib/effects/trail")
  electric = require("wf-lib/electric/damage")
  taze_mine = require("wf-lib/electric/taze_mine")
  fx.install{}
  wa.assets.load{
    sprites = {
      SHEET, BLADE,
      MASK_SPRITES[1], MASK_SPRITES[2], MASK_SPRITES[3], MASK_SPRITES[4],
      MASK_SPRITES[5], MASK_SPRITES[6], MASK_SPRITES[7], MASK_SPRITES[8],
      MASK_SPRITES[9], MASK_SPRITES[10], MASK_SPRITES[11], MASK_SPRITES[12],
      fx.SPARK, fx.BLOB, fx.SMOKE, trail.BEAM, trail.GLOW,
    },
    sounds = { CUT[1], CUT[2], CUT[3], CUT[4], CLANK, SHOCK },
    gpu_prefix = "sprites/saw/",
  }
  -- CurWorm. Also used for when a grenade is launched and the worm's turn ends. Reliable.
  -- If obj is launched, the saw shouldnt be rogue.
  wa.on.worm_message(function(worm)
    -- Avoids constant O(n) aswell.
    if worm.turn then current_turn_worm = worm end  
  end, { msgs = { wa.msg.FRAME_FINISH}})
  wa.on.turn_start(function()
    turn_active = true
    -- PX resets timesSliced/sawhitlimit at preturn. Its hitFrame is per-worm
    -- and technically survives a turn boundary, but this port clears the Lua
    -- gates too so a stale frame from the previous round cannot block hits.
    worm_slices, worm_next, worm_taze = {}, {}, {}
    obj_hits, obj_next = {}, {}
    for i = 1, #saws do
      local s = saws[i]
      reset_turn(s)
      -- Even a pinned actor can be gone (WA's own cleanup); without a
      -- controller the saw never ticks again, so rebuild it for this turn.
      if not s.controller or s.controller.id == 0 then
        s.controller = spawn_controller(s)
      end
    end
  end)
  wa.on.turn_end(function() turn_active = false end)
  wa.on.draw(draw)
end

function M.spawn(o)
  if not installed or not o or not o.x or not o.y then return nil end
  local size = math.max(0.1, math.min(1.0, o.size or 0.5))
  local s = {
    x = o.x, y = o.y, size = size, radius = 100 * size,
    team = o.team,
    electric = false, ring = nil,
    angle = 0, rotation = wa.random(-125, -80) / 1000,
    times_collided = 0, hits_this_turn = 0, transition = false,
    stop_rotation = false, missile_frames = {},
    depth = o.depth or (wa.depth.OBJECTS + 1)
  }
  -- `visible=false` would also drop the sprite id the mask is built from, so
  -- keep the mask sprite and draw it as additive black to hide it.
  s.controller = spawn_controller(s)
  if not s.controller then return nil end
  saws[#saws + 1] = s
  if o.electric then M.zap(s) end
  return s
end

function M.zap(s)
  if not s or s.electric then return end
  s.electric = true
  local kind = wa.random(1, 3)
  local radius = s.radius
  local opts
  if kind == 2 then
    opts = { radius = radius * 0.75, segments = 12, noise = 3.5,
      r = 80, g = 140, b = 255, depth = s.depth - 1, speed = 0.03 }
  elseif kind == 1 then
    opts = { radius = radius * 0.75, segments = 22, noise = 5.1,
      r = 167, g = 210, b = 255, depth = s.depth - 1 }
  else
    opts = { radius = radius * 0.67, segments = 25, noise = 0.67,
      r = 167, g = 210, b = 255, depth = s.depth - 1 }
  end
  opts.x, opts.y, opts.owner = s.x, s.y, s.controller
  opts.follow = function() return s.x, s.y end
  s.ring = kind == 2 and fx.thin_spin(opts) or fx.ring(opts)
  play(s, SHOCK)
end

function M.on_weapon_explode(ev, size, sound1, sound2)
  if not ev or not ev.x or not ev.y then return nil end
  local shooter = shooter_of(ev)
  local team = shooter and shooter.alliance or 0
  local s = M.spawn{ x = ev.x, y = ev.y, size = size, team = team }
  if s then
    play(s, sound1)
    play(s, sound2)
  end
  return s
end

return M