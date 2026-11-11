-- Stress test: four batches of projectiles in the first turn, to record and replay.

return function()
  local START_DELAY = 50
  local COUNT = 40 -- projectiles per batch
  local BATCH_GAP = 400
  local DAMAGE = 15 -- each explosion's damage
  local BLAST = 40
  local PROFILE = true
  local SEED = 12345
  local MAGNETS = 6 -- first; needs Highlander's Electromagnet placed
  local MAGNET = "px.electromagnet"
  local BOWLING_STRIKES = 7 -- batch 3; needs its Bowling Ball Strike placed
  local BOWLING = "px.bowling_ball_strike"
  local ELECTRIC_GRENADES = 50 -- batch 4; needs its Electric Grenade placed
  local ELECTRIC = "px.electric_grenade"
  local ELECTRIC_FUSE = 3000 -- ms, plus up to ELECTRIC_SPREAD
  local ELECTRIC_SPREAD = 1500
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

  if PROFILE then
    wa.perf.enable({ profile = true })
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
    local launched, refused, reason = 0, 0, nil
    for _, p in ipairs(electric_points()) do
      local ok, err = pcall(wa.weapons.launch, {
        weapon = ELECTRIC, owner = owner,
        x = p.x, y = p.y, vx = (rand(5) - 2) * (1 / 2), vy = 0,
        missile = { fuse = ELECTRIC_FUSE + rand(ELECTRIC_SPREAD) },
      })
      if ok then
        launched = launched + 1
      else
        refused, reason = refused + 1, reason or tostring(err)
      end
    end
    wa.log(string.format("stress: batch 4, %d of %d Electric Grenades launched%s", launched,
      ELECTRIC_GRENADES, refused > 0 and (", " .. refused .. " refused: " .. reason) or ""))
  end

  local function ground(x)
    local size = wa.world.size()
    local y = 20
    while y < size.h and wa.land.solid(x, y) do y = y + 4 end
    while y < size.h and not wa.land.solid(x, y) do y = y + 4 end
    return y
  end

  local function bowling_batch(owner)
    local size = wa.world.size()
    local fired, reason = 0, nil
    for i = 1, BOWLING_STRIKES do
      local x = size.w * i // (BOWLING_STRIKES + 1)
      local ok, err = pcall(wa.weapons.click, {
        weapon = BOWLING, worm = owner, x = x, y = ground(x),
        vx = (i % 2 == 1) and 1 or -1, -- the strike's direction: odd ones from the left
      })
      if ok then fired = fired + 1 else reason = reason or tostring(err) end
    end
    wa.log(string.format("stress: batch 3, %d of %d Bowling Ball Strikes%s", fired, BOWLING_STRIKES,
      reason and (", " .. reason) or ""))
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
    wa.log(string.format("stress: %d of %d Electromagnets (%d attracting)%s", fired, MAGNETS, attract,
      reason and (", " .. reason) or ""))
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
  end

  local now = 0
  local orbs = {}
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
        scale = 1.0 + 0.6 * wa.math.sin(now / 6)
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
      o.id = o.a.id
      orbs[o.id] = o
    end
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

  local started = false
  wa.on.turn_start(function(ev)
    if started then
      return
    end
    started = true
    local owner = ev.worm
    local shots = plan()
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
        if now == START_DELAY then
          local w = live_owner(owner)
          if w then
            if MAGNETS > 0 then magnet_batch(w) end
            wa.log(string.format("stress: batch 1, %d stock projectiles (mortar, cluster bomb)", COUNT))
            stock_batch(w, shots)
          else
            wa.log("stress: batch 1 skipped, no worm alive to fire it for")
          end
        end
        if now == START_DELAY + BATCH_GAP then
          local w = live_owner(owner)
          if w then
            wa.log(string.format("stress: batch 2, %d custom projectiles (Lua actors, GPU orbs)", COUNT))
            custom_batch(w, shots)
          else
            wa.log("stress: batch 2 skipped, no worm alive to fire it for")
          end
        end
        if now == START_DELAY + 2 * BATCH_GAP and BOWLING_STRIKES > 0 then
          local w = live_owner(owner)
          if w then
            bowling_batch(w)
          else
            wa.log("stress: batch 3 skipped, no worm alive to fire it for")
          end
        end
        if now == START_DELAY + 3 * BATCH_GAP and ELECTRIC_GRENADES > 0 then
          local w = live_owner(owner)
          if w then
            electric_batch(w)
          else
            wa.log("stress: batch 4 skipped, no worm alive to fire it for")
          end
        end
        local last = START_DELAY
          + (ELECTRIC_GRENADES > 0 and 3 * BATCH_GAP or BOWLING_STRIKES > 0 and 2 * BATCH_GAP or BATCH_GAP)
        if now > last and next(orbs) == nil and #flashes == 0 then
          a:despawn()
        end
      end,
    })
  end)

  local function argb(alpha, rgb)
    return (alpha << 24) | rgb
  end

  local QUAD = { sprite = GLOW, blend = "add", colors = {0, 0, 0, 0},
    points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} } }
  local function glow(x, y, half, c1, c2, c3, c4)
    local p, c = QUAD.points, QUAD.colors
    p[1][1], p[1][2] = x - half, y - half
    p[2][1], p[2][2] = x + half, y - half
    p[3][1], p[3][2] = x + half, y + half
    p[4][1], p[4][2] = x - half, y + half
    c[1], c[2], c[3], c[4] = c1, c2, c3, c4
    wa.draw.quad(QUAD)
  end

  wa.on.draw(function()
    for _, o in pairs(orbs) do
      local x, y, t = o.a.x, o.a.y, o.tint
      local c = TINTS[(o.a.id % #TINTS) + 1]
      glow(x, y, 48, argb(0xFF, t), argb(0xFF, c), argb(0xFF, c), argb(0xFF, t))
      glow(x, y, 16, argb(0xFF, 0xFFFFFF), argb(0xFF, 0xFFFFFF), argb(0xFF, 0xFFFFFF), argb(0xFF, 0xFFFFFF))
      for i, p in ipairs(o.trail) do
        local a = argb(0xFF - (i - 1) * 0x1C, t)
        glow(p.x, p.y, (30 - i * 2), a, a, a, a)
      end
    end
    for _, f in ipairs(flashes) do
      local age = now - f.born
      local alpha = 0xFF * (FLASH - age) // FLASH
      local a, white = argb(alpha, f.tint), argb(alpha, 0xFFFFFF)
      glow(f.x, f.y, (30 + age * 26 // 10), a, a, a, a)
      glow(f.x, f.y, (16 + age), white, white, white, white)
    end
  end)
end
