-- Stress test: batches of projectiles and effects in the first turn, each logged, to record and replay.

return function()
  local START_DELAY = 50
  local BATCH_GAP = 400 -- frames each batch has before the next
  local COUNT = 40 -- projectiles in the stock and orb batches
  local DAMAGE = 15 -- each explosion's damage
  local BLAST = 40
  local PROFILE = true
  local SEED = 12345
  local MAGNETS = 6 -- with the stock batch
  local MAGNET = "px.electromagnet"
  local BOWLING_STRIKES = 7
  local BOWLING = "px.bowling_ball_strike"
  local ELECTRIC_GRENADES = 50
  local ELECTRIC = "px.electric_grenade"
  local ELECTRIC_FUSE = 3000 -- ms, plus up to ELECTRIC_SPREAD
  local ELECTRIC_SPREAD = 1500
  local FIRE_CLUSTERS = 8 -- five clustlets each, each bursting into fire
  local FIRE_CLUSTER = "px.fire_cluster_bomb"
  local LIGHTNING_STRIKES = 6
  local LIGHTNING = "px.lightning_strike"
  local SAWS = 5 -- only when the Saw (Red Saw mod) is placed
  local SAW = "px.saw_grenade"
  local TOXIC_GRENADES = 4 -- about 720 puffs; last, as the clouds stay
  local TOXIC = "px.toxic_grenade"
  local ORB, GLOW = "stress/sprites/orb", "stress/sprites/glow"
  local TINTS = { 0xFF4040, 0xFFA030, 0xF0F040, 0x50E060, 0x40C0FF, 0xA070FF }
  local STYLES = {
    { name = "alpha", blend = "normal" },
    { name = "add", blend = "add", scale = 1.6 },
    { name = "pulse", blend = "normal", pulse = true },
    { name = "behind", blend = "normal", depth = wa.depth.BEHIND_TERRAIN }, -- terrain is 0x180000
  }
  local TRAIL = 8 -- glows behind each orb
  local TRAIL_EVERY = 4 -- frames between them, so the trail lingers
  local FLASH = 50 -- frames an explosion's flash lasts

  wa.assets.load({ sprites = { ORB, GLOW }, gpu_prefix = "stress/sprites/" })

  -- One `perf:` line a second: tools/stress-report.py sums the ones inside each batch.
  if PROFILE then
    wa.perf.enable({ profile = true, every = 1 })
    wa.hud.fps_counter()
  end

  local seed = SEED
  local function rand(n)
    seed = (seed * 1103515245 + 12345) % 0x80000000
    return seed * n // 0x80000000
  end

  local function plan()
    local size = wa.world.size()
    local shots = {}
    for i = 1, COUNT do
      local x = size.w * i // (COUNT + 1) + rand(41) - 20
      local y = 20
      while y < size.h and wa.land.solid(x, y) do
        y = y + 8
      end
      shots[i] = {
        x = x,
        y = (y + 10 + rand(40)),
        vx = (rand(9) - 4) * (1 / 2),
        vy = rand(3),
      }
    end
    return shots
  end

  local function ground(x)
    local size = wa.world.size()
    local y = 20
    while y < size.h and wa.land.solid(x, y) do y = y + 4 end
    while y < size.h and not wa.land.solid(x, y) do y = y + 4 end
    return y
  end

  local function report(name, done, wanted, reason)
    wa.log(string.format("stress: %s, %d of %d%s", name, done, wanted, reason and (", " .. reason) or ""))
  end

  local function electric_points()
    local size = wa.world.size()
    local water = wa.world.water() // 1
    if water <= 0 then water = size.h end -- not known: the whole height
    local points = {}
    for i = 1, ELECTRIC_GRENADES do
      for _ = 1, 20 do
        local x = 20 + rand(math.max(1, size.w - 40))
        local y = 20 + rand(math.max(1, math.min(size.h, water) - 40))
        if not wa.land.solid(x, y) then
          points[#points + 1] = { x = x, y = y }
          break
        end
      end
    end
    return points
  end

  local function electric_batch(owner)
    local launched, reason = 0, nil
    for _, p in ipairs(electric_points()) do
      local ok, err = pcall(wa.weapons.launch, {
        weapon = ELECTRIC, owner = owner,
        x = p.x, y = p.y, vx = (rand(5) - 2) * (1 / 2), vy = 0,
        missile = { fuse = ELECTRIC_FUSE + rand(ELECTRIC_SPREAD) },
      })
      if ok then launched = launched + 1 else reason = reason or tostring(err) end
    end
    report("Electric Grenades", launched, ELECTRIC_GRENADES, reason)
  end

  -- `count` of a placed thrown weapon, spread over the map above the ground.
  local function launch_batch(name, weapon, count, owner)
    local size = wa.world.size()
    local launched, reason = 0, nil
    for i = 1, count do
      local x = size.w * i // (count + 1) + rand(41) - 20
      local ok, err = pcall(wa.weapons.launch, {
        weapon = weapon, owner = owner,
        x = x, y = ground(x) - 60, vx = (rand(5) - 2) * (1 / 2), vy = 0,
      })
      if ok then launched = launched + 1 else reason = reason or tostring(err) end
    end
    report(name, launched, count, reason)
    return launched
  end

  local function click_batch(name, weapon, count, owner)
    local size = wa.world.size()
    local fired, reason = 0, nil
    for i = 1, count do
      local x = size.w * i // (count + 1)
      local ok, err = pcall(wa.weapons.click, {
        weapon = weapon, worm = owner, x = x, y = ground(x),
        vx = (i % 2 == 1) and 1 or -1, -- a strike's direction: odd ones from the left
      })
      if ok then fired = fired + 1 else reason = reason or tostring(err) end
    end
    report(name, fired, count, reason)
  end

  local function magnet_batch(owner)
    local size = wa.world.size()
    local fired, attract, reason = 0, 0, nil
    for i = 1, MAGNETS do
      local x = size.w * i // (MAGNETS + 1) + rand(41) - 20
      local polarity = rand(2) == 0 and 1 or -1
      local ok, err = pcall(wa.weapons.fire, {
        weapon = MAGNET, worm = owner, x = x, y = (ground(x) - 30), polarity = polarity,
      })
      if ok then
        fired = fired + 1
        if polarity < 0 then attract = attract + 1 end
      else
        reason = reason or tostring(err)
      end
    end
    report(string.format("Electromagnets (%d attracting)", attract), fired, MAGNETS, reason)
  end

  local function stock_batch(owner, shots)
    for i, s in ipairs(shots) do
      local cluster = i % 2 == 0
      wa.weapons.launch({
        weapon = cluster and "stock.cluster_bomb" or "stock.mortar",
        owner = owner,
        x = s.x, y = s.y, vx = s.vx, vy = s.vy,
        missile = { explosion = { power = DAMAGE }, fuse = cluster and 3000 or nil },
      })
    end
    report("stock projectiles (mortar, cluster bomb)", #shots, COUNT)
  end

  local now = 0
  local orbs = {}
  local flashes = {} -- { x, y, tint, born }

  local function orb_brain(o)
    local spin = 0
    return function(a)
      a.vy = a.vy + wa.world.gravity()
      local hit = a:move({ terrain = true, worms = true })
      if hit.terrain or hit.land or hit.worm then
        flashes[#flashes + 1] = { x = a.x, y = a.y, tint = o.tint, born = now }
        orbs[o.id] = nil
        a:explode({ damage = DAMAGE, id = BLAST })
        a:remove()
        return
      end
      if now % TRAIL_EVERY == 0 then
        table.insert(o.trail, 1, { x = a.x, y = a.y })
        o.trail[TRAIL + 1] = nil
      end
      spin = (spin + 12) % 360
      local scale = o.style.scale or 1.0
      if o.style.pulse then
        scale = 1.0 + 0.6 * wa.math.sin(now / 6)
      end
      a:gfx({ angle = spin, tint = o.tint, blend = o.style.blend, scale = scale, depth = o.style.depth })
      a:advance()
      if a:in_water() then
        orbs[o.id] = nil
        a:remove()
      end
    end
  end

  local function custom_batch(owner, shots)
    for i, s in ipairs(shots) do
      local o = { tint = TINTS[(i - 1) % #TINTS + 1], style = STYLES[(i - 1) % #STYLES + 1], trail = {} }
      o.a = wa.actors.spawn({
        sprite = ORB,
        x = s.x, y = s.y, vx = s.vx, vy = s.vy,
        owner = owner,
        on = orb_brain(o),
      })
      o.id = o.a.id
      orbs[o.id] = o
    end
    report("custom projectiles (Lua actors, GPU orbs)", #shots, COUNT)
  end

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

  local function batches(shots)
    return {
      { name = "stock", run = function(w)
        if MAGNETS > 0 then magnet_batch(w) end
        stock_batch(w, shots)
      end },
      { name = "orbs", run = function(w) custom_batch(w, shots) end },
      { name = "bowling", run = function(w) click_batch("Bowling Ball Strikes", BOWLING, BOWLING_STRIKES, w) end },
      { name = "electric", run = electric_batch },
      { name = "fire", run = function(w) launch_batch("Fire Cluster Bombs", FIRE_CLUSTER, FIRE_CLUSTERS, w) end },
      { name = "lightning", run = function(w) click_batch("Lightning Strikes", LIGHTNING, LIGHTNING_STRIKES, w) end },
      { name = "saws", run = function(w)
        if launch_batch("Saws", SAW, SAWS, w) == 0 then
          wa.log("stress: no saws: place the Saw from the Red Saw mod on the panel for this batch")
        end
      end },
      { name = "toxic", run = function(w) launch_batch("Toxic Grenades", TOXIC, TOXIC_GRENADES, w) end },
    }
  end

  local started = false
  wa.on.turn_start(function(ev)
    if started then
      return
    end
    started = true
    local owner = ev.worm
    local shots = plan()
    local list = batches(shots)
    local size = wa.world.size()
    local worms, teams = 0, {}
    for _, w in ipairs(wa.worms.all()) do
      worms = worms + 1
      teams[w.team] = true
    end
    local team_count = 0
    for _ in pairs(teams) do team_count = team_count + 1 end
    wa.log(string.format("stress: start, %d worms in %d teams, map %dx%d, seed %d, %d batches %d frames apart",
      worms, team_count, size.w, size.h, SEED, #list, BATCH_GAP))
    local finish = START_DELAY + #list * BATCH_GAP
    wa.actors.spawn({
      sprite = false, x = shots[1].x, y = shots[1].y,
      owner = owner,
      on = function(a)
        now = now + 1
        for i = #flashes, 1, -1 do
          if now - flashes[i].born >= FLASH then
            table.remove(flashes, i)
          end
        end
        local at = now - START_DELAY
        if at >= 0 and at % BATCH_GAP == 0 then
          local i = at // BATCH_GAP + 1
          local batch = list[i]
          if batch then
            -- The marker tools/stress-report.py splits the log at.
            wa.log(string.format("stress: batch %d %s at frame %d", i, batch.name, wa.world.frame()))
            local w = live_owner(owner)
            if w then
              batch.run(w)
            else
              wa.log("stress: " .. batch.name .. " skipped, no worm alive to fire it for")
            end
          end
        end
        if now == finish then
          wa.log(string.format("stress: end at frame %d", wa.world.frame()))
        end
        if now > finish and next(orbs) == nil and #flashes == 0 then
          a:remove()
        end
      end,
    })
  end)

  local function argb(alpha, rgb)
    return (alpha << 24) | rgb
  end

  -- Every glow of a frame in one list: nine numbers a quad, drawn in one call.
  local MAX = 4096
  local batch = { sprite = GLOW, blend = "add", quads = {}, count = 0 }
  local q, n = batch.quads, 0
  local function glow(x, y, half, color)
    q[n + 1], q[n + 2] = x - half, y - half
    q[n + 3], q[n + 4] = x + half, y - half
    q[n + 5], q[n + 6] = x + half, y + half
    q[n + 7], q[n + 8] = x - half, y + half
    q[n + 9] = color
    n = n + 9
    if n == MAX * 9 then
      batch.count = MAX
      wa.draw.quads(batch)
      n = 0
    end
  end

  wa.on.draw(function()
    n = 0
    for _, o in pairs(orbs) do
      local x, y, t = o.a.x, o.a.y, o.tint
      glow(x, y, 48, argb(0xFF, t))
      glow(x, y, 16, argb(0xFF, 0xFFFFFF))
      for i, p in ipairs(o.trail) do
        glow(p.x, p.y, (30 - i * 2), argb(0xFF - (i - 1) * 0x1C, t))
      end
    end
    for _, f in ipairs(flashes) do
      local age = now - f.born
      local alpha = 0xFF * (FLASH - age) // FLASH
      glow(f.x, f.y, (30 + age * 26 // 10), argb(alpha, f.tint))
      glow(f.x, f.y, (16 + age), argb(alpha, 0xFFFFFF))
    end
    if n > 0 then
      batch.count = n // 9
      wa.draw.quads(batch)
    end
  end)
end
