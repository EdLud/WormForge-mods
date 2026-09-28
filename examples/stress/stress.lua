-- Stress test: two batches of projectiles in the first turn of the match, to
-- measure WA's own projectiles against WormForge's, and to record into a
-- replay that can be played back again and again for sync and performance.
--
-- Batch 1, when the first turn starts: STOCK. Real WA missiles
-- (wa.weapons.launch) that WA flies, draws and explodes itself: mortar shells
-- that burst into clustlets on impact (drawn by WormForge as particles), and
-- cluster bombs on a 3 s fuse.
-- Batch 2, BATCH_GAP frames later in the same turn: CUSTOM. Lua actors with
-- this pack's truecolor orb, falling under the actor physics and exploding
-- with WA's explosion where they hit, drawn on the GPU in four styles:
--
--   alpha    spun and tinted, normal blending
--   add      additive, at 1.6x
--   pulse    its scale breathing
--   behind   behind the terrain, so the land hides it where they overlap
--
-- and, every rendered frame (wa.on.draw), a large additive halo with a colour
-- per corner and a white-hot core, a trail of eight fading glows behind each
-- orb (one every fourth frame, so it lingers), and an additive flash, growing to about 320 pixels across, for a
-- second where each one explodes.
--
-- Both batches start from the same positions and speeds, so the two halves of
-- the turn compare like for like. Everything that decides what happens runs
-- in simulation callbacks, from a private generator with a fixed seed: the
-- same on every machine, and again in every replay of the match. The drawing
-- only reads it.
--
-- With PROFILE on, the pack also turns on the FPS counter and the profiler
-- (see mods/examples/perf). wkLua.log gets a "stress:" line when each batch
-- goes, between the profiler's "perf:" lines.
--
-- The pack claims Nuclear Test only to carry its two sheets into the GPU atlas
-- (`gpu_prefix`); the weapon itself stays WA's.

local COUNT = 40        -- projectiles per batch
local BATCH_GAP = 400   -- frames from batch 1 to batch 2: 8 s at WA's 50 a second
local DAMAGE = 15       -- each explosion's damage
local BLAST = 40        -- each custom explosion's size (CreateExplosion's id)
local PROFILE = true
local SEED = 12345

local FX = 0x10000
local ORB, GLOW = "sprites/orb", "sprites/glow"
local TINTS = { 0xFF4040, 0xFFA030, 0xF0F040, 0x50E060, 0x40C0FF, 0xA070FF }
local STYLES = {
  { name = "alpha", blend = "normal" },
  { name = "add", blend = "add", scale = 1.6 },
  { name = "pulse", blend = "normal", pulse = true },
  { name = "behind", blend = "normal", depth = 0x190000 }, -- terrain is 0x180000
}
local TRAIL = 8         -- glows behind each orb
local TRAIL_EVERY = 4   -- frames between them, so the trail lingers
local FLASH = 50        -- frames an explosion's flash lasts

wa.weapons.replace({
  weapon = "nuclear_test",
  sprites = { ORB, GLOW },
  params = { gpu_prefix = "sprites/" },
})

if PROFILE then
  wa.perf.enable({ counter = true, profile = true })
end

-- A linear congruential generator: the same numbers on every machine, and
-- without touching WA's RNG, so WA's own random draws are left as they were.
local seed = SEED
local function rand(n)
  seed = (seed * 1103515245 + 12345) % 0x80000000
  return seed % n
end

-- Where each projectile starts, and how fast: spread across the map, from
-- the first open air under its top (on a cavern, under the roof).
local function plan()
  local size = wa.world.size()
  local shots = {}
  for i = 1, COUNT do
    local x = size.w * i // (COUNT + 1) + rand(41) - 20
    local y = 20
    while y < size.h and wa.land.solid(x * FX, y * FX) do
      y = y + 8
    end
    shots[i] = {
      x = x * FX,
      y = (y + 10 + rand(40)) * FX,
      vx = (rand(9) - 4) * FX // 2,
      vy = rand(3) * FX,
    }
  end
  return shots
end

local function stock_batch(owner, shots)
  for i, s in ipairs(shots) do
    local cluster = i % 2 == 0
    wa.weapons.launch({
      weapon = cluster and "cluster_bomb" or "mortar",
      owner = owner,
      x = s.x, y = s.y, vx = s.vx, vy = s.vy,
      damage = DAMAGE,
      fuse = cluster and 3000 or nil,
    })
  end
end

-- Simulation state the drawing reads: the frame count, the live orbs (with
-- their last positions) and the explosions still flashing.
local now = 0
local orbs = {}    -- actor id -> { a, id, tint, style, trail = { {x, y}, ... } }
local flashes = {} -- { x, y, tint, born }

local function orb_brain(o)
  local spin = 0
  return function(a)
    a:gravity()
    local hit = a:move({ terrain = true, worms = true })
    if hit.terrain or hit.land or hit.worm then
      flashes[#flashes + 1] = { x = a.x, y = a.y, tint = o.tint, born = now }
      orbs[o.id] = nil
      a:explode({ damage = DAMAGE, id = BLAST })
      a:despawn()
      return
    end
    if now % TRAIL_EVERY == 0 then
      table.insert(o.trail, 1, { x = a.x, y = a.y })
      o.trail[TRAIL + 1] = nil
    end
    spin = (spin + 12) % 360
    local scale = o.style.scale or 1.0
    if o.style.pulse then
      scale = 1.0 + 0.6 * math.sin(now / 6)
    end
    a:gfx({ angle = spin, tint = o.tint, blend = o.style.blend, scale = scale, depth = o.style.depth })
    a:advance()
    if a:in_water() then
      orbs[o.id] = nil
      a:despawn()
    end
  end
end

local function custom_batch(owner, shots)
  for i, s in ipairs(shots) do
    local o = { tint = TINTS[(i - 1) % #TINTS + 1], style = STYLES[(i - 1) % #STYLES + 1], trail = {} }
    o.a = wa.actors.spawn({
      sprite = ORB,
      x = s.x, y = s.y, vx = s.vx, vy = s.vy,
      gravity = false, collide = false, owner = owner,
      on = orb_brain(o),
    })
    -- Registered here, not on its first tick: the clock may run first.
    o.id = o.a.id
    orbs[o.id] = o
  end
end

-- A worm to fire batch 2 for: the first turn's, or any worm still alive.
local function live_owner(first)
  if first and first.hp > 0 then
    return first
  end
  for _, w in ipairs(wa.worms.all()) do
    if w.hp > 0 then
      return w
    end
  end
end

local started = false
wa.on.turn_start(function(ev)
  if started then
    return
  end
  started = true
  local owner = ev.worm
  local shots = plan()
  wa.log(string.format("stress: batch 1, %d stock projectiles (mortar, cluster bomb)", COUNT))
  stock_batch(owner, shots)
  -- The clock: an invisible actor whose brain counts frames, fires batch 2
  -- and lets the flashes go. It runs every frame whatever the worms do, and
  -- in lockstep.
  wa.actors.spawn({
    sprite = false, x = shots[1].x, y = shots[1].y,
    gravity = false, collide = false, owner = owner,
    on = function(a)
      now = now + 1
      for i = #flashes, 1, -1 do
        if now - flashes[i].born >= FLASH then
          table.remove(flashes, i)
        end
      end
      if now == BATCH_GAP then
        local w = live_owner(owner)
        if w then
          wa.log(string.format("stress: batch 2, %d custom projectiles (Lua actors, GPU orbs)", COUNT))
          custom_batch(w, shots)
        else
          wa.log("stress: batch 2 skipped, no worm alive to fire it for")
        end
      end
      if now > BATCH_GAP and next(orbs) == nil and #flashes == 0 then
        a:despawn()
      end
    end,
  })
end)

-- Drawing: reads the state above, never writes it.
local function argb(alpha, rgb)
  return (alpha << 24) | rgb
end

local function glow(x, y, half, colors)
  wa.draw.quad({
    points = { { x - half, y - half }, { x + half, y - half }, { x + half, y + half }, { x - half, y + half } },
    colors = colors,
    sprite = GLOW,
    blend = "add",
  })
end

wa.on.draw(function()
  for _, o in pairs(orbs) do
    local x, y, t = o.a.x, o.a.y, o.tint
    -- The halo: a colour per corner, the orb's own at the top left, and a
    -- white-hot core over it.
    local c = TINTS[(o.a.id % #TINTS) + 1]
    glow(x, y, 48 * FX, { argb(0xFF, t), argb(0xFF, c), argb(0xFF, c), argb(0xFF, t) })
    glow(x, y, 16 * FX, { argb(0xFF, 0xFFFFFF), argb(0xFF, 0xFFFFFF), argb(0xFF, 0xFFFFFF), argb(0xFF, 0xFFFFFF) })
    for i, p in ipairs(o.trail) do
      local a = argb(0xFF - (i - 1) * 0x1C, t)
      glow(p.x, p.y, (30 - i * 2) * FX, { a, a, a, a })
    end
  end
  for _, f in ipairs(flashes) do
    local age = now - f.born
    local alpha = 0xFF * (FLASH - age) // FLASH
    local a, white = argb(alpha, f.tint), argb(alpha, 0xFFFFFF)
    glow(f.x, f.y, (30 + age * 26 // 10) * FX, { a, a, a, a })
    glow(f.x, f.y, (16 + age) * FX, { white, white, white, white })
  end
end)
