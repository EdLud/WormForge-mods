-- Weather tests: lightning, where rain and snow draw, rings at the shore, settling and melting snow, the cycle.
-- Run from the mods repository's root: lua tests/weather/test_weather.lua
local ROOT = (arg and arg[0] or ""):match("^(.*)tests/weather/") or "./"

local failed = 0
local function check(name, ok, detail)
  print((ok and "  ok   " or "  FAIL ") .. name .. (ok and "" or ("   [" .. tostring(detail) .. "]")))
  if not ok then failed = failed + 1 end
end

-- The engine's require: weather's own modules, and wf.sdk's under wf-lib/.
local modules = {}
local function load_module(name)
  if modules[name] ~= nil then return modules[name] end
  local path = name:sub(1, 7) == "wf-lib/" and (ROOT .. "sdk/" .. name:sub(8) .. ".lua")
    or (ROOT .. "weather/" .. name .. ".lua")
  local env = setmetatable({ require = load_module }, { __index = _G })
  local result = assert(loadfile(path, "t", env))()
  modules[name] = result == nil and true or result
  return modules[name]
end

-- A level 2000 wide, water at 560, a cliff left of x 200 from y 400 down.
local M
-- The objects near a point, as `wa.<kind>.all{ near = { x, y, r } }` gives them.
local function listing(get)
  return function(opts)
    local list = get()
    if not (opts and opts.near) then return list end
    local x, y, r = opts.near[1], opts.near[2], opts.near[3]
    local out = {}
    for _, o in ipairs(list) do
      if (o.x - x) * (o.x - x) + (o.y - y) * (o.y - y) <= r * r then out[#out + 1] = o end
    end
    return out
  end
end

local RAIN = { rain = 80, wind = 100, clouds = 70, darkness = 25, ripples = true,
  lightning_chance = 100, lightning_effect = "strike", volume = 70 }
local SNOW = { snow = 60, wind = 100, clouds = 70, settle = false, settle_depth = 10, volume = 50 }
local CYCLE = { change_chance = 35, rain_weight = 40, snow_weight = 40, clear_weight = 20, start = "random", melt = 4 }

local function merged(defaults, given)
  local out = {}
  for k, v in pairs(defaults) do out[k] = v end
  for k, v in pairs(given or {}) do out[k] = v end
  return { option = function(key)
    assert(out[key] ~= nil, "no option " .. key)
    return out[key]
  end }
end

-- `options` for Rain (false: Rain not selected); `extra.snow` / `extra.cycle` select those too.
local function new_match(options, extra)
  extra = extra or {}
  modules = {}
  local seed = 12345
  local function next_int()
    seed = (seed * 1103515245 + 12345) % 0x80000000
    return seed
  end
  M = { frame = 0, draws = {}, turn_starts = {}, turn_ends = {}, spawned = {}, quads = {}, quad = {}, quad_boxes = {},
    ribbons = {}, mines = {}, oil = {}, crates = {}, worms = {}, graves = {}, sounds = {}, ambients = {}, logs = {},
    stamps = {}, cuts = {} }
  local function solid(x, y) return x < 200 and y >= 400 end
  wa = {
    depth = { BEHIND_TERRAIN = 0x180000, TERRAIN = 0x180000, FRONT = 0x10000 },
    -- In a draw the engine resolves a key against whichever mod drew last: keys are taken at install.
    sprites = { key = function(p)
      assert(not M.drawing, "wa.sprites.key in a draw names another mod's sprite: " .. p)
      return p
    end },
    msg = {},
    draw = {
      random = function() return next_int() / 0x80000000 end,
      fraction = function() return 0 end,
      quads = function(b)
        M.quads[#M.quads + 1] = { sprite = b.sprite, frame = b.frame, depth = b.depth, count = b.count, colour = b.quads[9] }
        for i = 0, b.count - 1 do
          local l = b.quads
          M.quad_boxes[#M.quad_boxes + 1] = { sprite = b.sprite, depth = b.depth, top = l[i * 9 + 2], bottom = l[i * 9 + 6], left = l[i * 9 + 1] }
        end
      end,
      quad = function(q)
        M.quad[#M.quad + 1] = { sprite = q.sprite, depth = q.depth, blend = q.blend, uv = q.uv and { table.unpack(q.uv) } }
        M.quad_boxes[#M.quad_boxes + 1] = { sprite = q.sprite, depth = q.depth, top = q.points[1][2], bottom = q.points[3][2] }
        if q.colors and q.colors[3] >> 24 == 0 then M.fades = (M.fades or 0) + 1 end
        if q.colors and q.colors[1] >> 24 == 0 then M.fades_in = (M.fades_in or 0) + 1 end
      end,
      ribbon = function(r)
        local pts = {}
        for i, p in ipairs(r.points) do pts[i] = { x = p.x, y = p.y } end
        M.ribbons[#M.ribbons + 1] = { sprite = r.sprite, depth = r.depth, points = pts }
      end,
    },
    on = {
      draw = function(f) M.draws[#M.draws + 1] = f end,
      turn_start = function(f) M.turn_starts[#M.turn_starts + 1] = f end,
      turn_end = function(f) M.turn_ends[#M.turn_ends + 1] = f end,
    },
    log = function(line) M.logs[#M.logs + 1] = line end,
    world = {
      view = function() return { cx = 500, cy = 300, w = 1000, h = 600, zoom = 1 } end,
      frame = function() return M.frame end,
      wind = function() return 0.1 end,
      water = function() return 560 end,
      size = function() return { w = 2000, h = 700 } end,
    },
    land = {
      solid = solid,
      trace = function(x0, y0, x1, y1)
        if solid(x0, y0) then return { x = x0, y = y0, starts_solid = true } end
        if x0 < 200 and y1 >= 400 then return { x = x0, y = 400 } end
        return nil
      end,
    },
    assets = { load = function(t) M.assets = t end },
    sound = {
      play = function(target, path) M.sounds[#M.sounds + 1] = path end,
      ambient = function(t)
        local h = { path = t.path, volume = t.volume }
        function h:set(s) self.volume = s.volume end
        M.ambients[t.path] = h
        M.ambient = M.ambient or t
        return h
      end,
    },
    actors = {
      spawn = function(spec)
        local a = { x = spec.x, y = spec.y, on = spec.on, owner = spec.owner }
        function a:despawn() self.dead = true end
        M.spawned[#M.spawned + 1] = a
        return a
      end,
      all = listing(function() return M.spawned end),
    },
    random = function(a, b) return a + next_int() % (b - a + 1) end,
    math = { cos = math.cos, sin = math.sin },
    mines = { all = listing(function() return M.mines end) },
    oil = { all = listing(function() return M.oil end) },
    crates = { all = listing(function() return M.crates end) },
    worms = { all = listing(function() return M.worms end) },
    graves = { all = listing(function() return M.graves end) },
  }
  if extra.cycle then load_module("features/weather_cycle")(merged(CYCLE, extra.cycle)) end
  if options ~= false then load_module("features/weather")(merged(RAIN, options)) end
  if extra.snow then load_module("features/snow")(merged(SNOW, extra.snow)) end
end

-- A turn of `team`'s worm starting, and ending.
local function turn(team, also_end)
  for _, f in ipairs(M.turn_starts) do f({ worm = { team = team, id = team * 16 } }) end
  if also_end ~= false then
    for _, f in ipairs(M.turn_ends) do f({}) end
  end
end

local function draw()
  M.quads, M.quad, M.quad_boxes, M.ribbons = {}, {}, {}, {}
  M.drawing = true
  for _, f in ipairs(M.draws) do f() end
  M.drawing = false
end

local function frames(n)
  for _ = 1, n do
    M.frame = M.frame + 1
    for _, a in ipairs(M.spawned) do if not a.dead then a.on(a) end end
    draw()
  end
end

-- Frames of the simulation alone, without drawing.
local function sim_frames(n)
  for _ = 1, n do
    M.frame = M.frame + 1
    for _, a in ipairs(M.spawned) do if not a.dead then a.on(a) end end
  end
end

-- A land of pixels: `ground(x, y)` at the start, then what stamps add and cuts take away.
local function pixel_land(ground)
  local settle = load_module("lib/settle")
  local added, removed = {}, {}
  local function key(x, y) return y * 100000 + x end
  local function solid(x, y)
    x, y = math.floor(x), math.floor(y)
    local k = key(x, y)
    if added[k] then return true end
    if removed[k] then return false end
    return ground(x, y)
  end
  local function pixels(t, each)
    for _, o in ipairs(settle.frame_pixels(t.frame)) do each(math.floor(t.x) + o[1], math.floor(t.y) + o[2]) end
  end
  wa.land.solid = solid
  wa.land.trace = function(x0, y0, x1, y1)
    if solid(x0, y0) then return { x = x0, y = y0, starts_solid = true, nx = 0, ny = -1 } end
    local dx, dy = x1 - x0, y1 - y0
    local n = math.ceil(math.max(math.abs(dx), math.abs(dy)) * 2)
    for i = 1, n do
      local x, y = x0 + dx * i / n, y0 + dy * i / n
      if solid(x, y) then
        local px, py = math.floor(x), math.floor(y)
        local sx = (solid(px + 1, py) and 1 or 0) - (solid(px - 1, py) and 1 or 0)
        local sy = (solid(px, py + 1) and 1 or 0) - (solid(px, py - 1) and 1 or 0)
        local len = math.sqrt(sx * sx + sy * sy)
        local nx, ny = 0, -1
        if len > 0 then nx, ny = -sx / len, -sy / len end
        return { x = px, y = py, nx = nx, ny = ny }
      end
    end
  end
  wa.land.stamp = function(t)
    M.stamps[#M.stamps + 1] = t
    pixels(t, function(x, y) added[key(x, y)] = true; removed[key(x, y)] = nil end)
  end
  wa.land.cut = function(t)
    M.cuts[#M.cuts + 1] = t
    pixels(t, function(x, y) removed[key(x, y)] = true; added[key(x, y)] = nil end)
  end
  local land = { solid = solid, added = added, removed = removed }
  -- Snow pixels by column, and the deepest column.
  function land.columns()
    local cols, deepest = {}, 0
    for k in pairs(added) do
      local x = k % 100000
      cols[x] = (cols[x] or 0) + 1
      if cols[x] > deepest then deepest = cols[x] end
    end
    return cols, deepest
  end
  -- Snow pixels with air right under them: standing on nothing.
  function land.floating()
    local n = 0
    for k in pairs(added) do
      if not solid(k % 100000, k // 100000 + 1) then n = n + 1 end
    end
    return n
  end
  function land.count()
    local n = 0
    for _ in pairs(added) do n = n + 1 end
    return n
  end
  return land
end

print("lightning chance: the try each second gives the chance a minute")
do
  new_match()
  local sim = load_module("lib/sim")
  check("0 % never strikes", sim.per_second(0) == 0)
  check("100 % strikes every second", sim.per_second(100) == 1000000)
  local last = 0
  local rising = true
  for p = 1, 99 do
    local q = sim.per_second(p)
    local exact = (1 - (1 - p / 100) ^ (1 / 60)) * 1000000
    if math.abs(q - exact) > 1 then check(p .. " % matches (1 - q)^60 = 1 - p", false, q .. " vs " .. exact) end
    if q <= last then rising = false end
    last = q
  end
  check("1..99 % rise and match (1 - q)^60 = 1 - p", rising)
end

print("lightning: strike aims at mines first and acts as the Lightning Strike")
do
  new_match()
  local mine = { kind = "mine", id = 1, x = 600, y = 300, fuse = 2500 }
  function mine:arm(ms) self.armed = ms end
  local worm = { kind = "worm", id = 2, x = 900, y = 300, hp = 50 }
  function worm:heal(n) self.hp = self.hp + n end
  M.mines, M.worms = { mine }, { worm }
  for _, f in ipairs(M.turn_starts) do f({}) end
  check("one clock actor, owned by no one", #M.spawned == 1 and M.spawned[1].owner == "none")
  frames(50)
  check("100 % strikes on the first second", #M.spawned >= 2)
  local strike = load_module("wf-lib/lightning").strikes[1]
  check("aimed at the mine", strike and math.abs(strike.ex - 600) < 1 and math.abs(strike.ey - 300) < 1,
    strike and (strike.ex .. "," .. strike.ey))
  frames(170)
  check("the mine starts with its own fuse", mine.armed == 2500)
  local hit = false
  for _, path in ipairs(M.sounds) do hit = hit or path == "wf-lib/px/sounds/lightning/hit.wav" end
  check("thunder as it starts, the hit as it lands",
    M.sounds[1] == "wf-lib/px/sounds/lightning/thunder.wav" and hit, table.concat(M.sounds, ","))
  check("the worm off the line keeps its health", worm.hp == 50)

  new_match({ lightning_effect = "looks" })
  M.mines = { mine }
  mine.armed = nil
  for _, f in ipairs(M.turn_starts) do f({}) end
  frames(220)
  check("looks: bolts but nothing struck", #M.spawned >= 2 and mine.armed == nil)

  new_match({ lightning_chance = 0 })
  for _, f in ipairs(M.turn_starts) do f({}) end
  check("0 %: no clock at all", #M.spawned == 0)
end

print("rain: where it draws")
do
  new_match()
  frames(3)
  local behind, front = 0, 0
  for _, q in ipairs(M.quads) do
    if q.sprite == "sprites/rain.png" then
      if q.depth >= wa.depth.BEHIND_TERRAIN then behind = behind + q.count end
      if q.depth == wa.depth.FRONT then front = front + q.count end
    end
  end
  check("far and mid rain behind the land", behind > 20, behind)
  check("heavy rain also in front of it", front > 0, front)
  local below, cut = 0, 0
  for _, q in ipairs(M.quad_boxes) do
    if q.sprite == "sprites/rain.png" and q.bottom > 560.01 then below = below + 1 end
  end
  for _, q in ipairs(M.quad) do
    if q.sprite == "sprites/rain.png" and q.uv and q.uv[4] < 1 then cut = cut + 1 end
  end
  check("no rain reaches under the water line", below == 0, below)
  check("the cells across it show only their part above", cut > 0, cut)
  check("the rain sound loops from the start", M.ambient and M.ambient.path == "sounds/rain.wav")
  check("the sheets are loaded with the lightning's",
    M.assets and #M.assets.sprites == 10 and #M.assets.sounds == 4, M.assets and #M.assets.sprites)

  new_match({ rain = 40 })
  frames(3)
  front = 0
  for _, q in ipairs(M.quads) do
    if q.sprite == "sprites/rain.png" and q.depth == wa.depth.FRONT then front = front + q.count end
  end
  check("light rain stays behind the land", front == 0)

  new_match({ rain = 0, clouds = 0, darkness = 0, lightning_chance = 0 })
  frames(3)
  check("nothing at all when everything is off", #M.quads == 0 and #M.ribbons == 0 and M.ambient == nil)
end

print("rings: they stop at the shore")
do
  local surface = (function() new_match(); return load_module("lib/surface") end)()
  local open = function(x) return x >= 200 end
  local l, r = surface.bounds(205, 26, 3, open)
  check("the bound sits on the open side of the shore", l >= 200 and l <= 203 and r == 229, l .. "," .. r)
  local a, b = surface.clip(205, 20, l, r)
  check("the ring is cut at the shore", a == l and b == 225)
  check("a ring wholly past its bound draws nothing", surface.clip(150, 20, 200, 300) == nil)

  new_match({ lightning_chance = 0 })
  local rings, whole, crossing, near_shore = 0, 0, 0, 0
  for _ = 1, 600 do
    frames(1)
    for _, rb in ipairs(M.ribbons) do
      if rb.sprite == "sprites/ring.png" and rb.depth == wa.depth.FRONT - 1 then
        rings = rings + 1
        for _, p in ipairs(rb.points) do
          if p.x < 200 then crossing = crossing + 1 end
          if p.x < 230 then near_shore = near_shore + 1 end
        end
      end
    end
    for _, q in ipairs(M.quads) do
      if q.sprite == "sprites/oval.png" and q.depth == wa.depth.FRONT - 1 then whole = whole + q.count end
    end
    for _, q in ipairs(M.quad_boxes) do
      if q.sprite == "sprites/oval.png" and q.depth == wa.depth.FRONT - 1 and q.left < 200 then crossing = crossing + 1 end
    end
  end
  check("rain rings the water: whole rings in one batch", whole > 100, whole)
  check("rings the shore cuts are drawn as arcs", rings > 20 and near_shore > 0, rings .. "," .. near_shore)
  check("no ring crosses into the cliff", crossing == 0, crossing)
end

print("sky: the clouds stand in the world")
do
  new_match({ rain = 0, darkness = 0, lightning_chance = 0 })
  local function clouds(cx, cy)
    wa.world.view = function() return { cx = cx, cy = cy, w = 1000, h = 600, zoom = 1 } end
    draw()
    local ys, xs = {}, {}
    for _, q in ipairs(M.quad_boxes) do
      if q.sprite == "wf-lib/px/sprites/lightning/cloud.png" then
        ys[#ys + 1], xs[#xs + 1] = q.top, q.left
      end
    end
    table.sort(ys); table.sort(xs)
    return ys, xs
  end
  local band = load_module("lib/sky").RAIN_TOP
  local high_y, high_x = clouds(500, band)
  local low_y = clouds(500, band + 40)
  local same = #high_y > 20 and #high_y == #low_y
  for i = 1, #high_y do same = same and high_y[i] == low_y[i] end
  check("moving the camera down leaves the clouds where they were", same, #high_y .. "," .. #low_y)
  local _, side_x = clouds(700, band)
  local shared = 0
  local at = {}
  for _, x in ipairs(high_x) do at[x] = true end
  for _, x in ipairs(side_x) do if at[x] then shared = shared + 1 end end
  check("and across: puffs keep their x as the view moves", shared > 10, shared)
  local far = clouds(500, 2000)
  check("a view far below the band draws none", #far == 0, #far)

  -- The rain comes out of the clouds: nothing above each layer's line, fading in under it.
  local sky = load_module("lib/sky")
  for _, clouds_on in ipairs({ 70, 0 }) do
    new_match({ clouds = clouds_on, darkness = 0, lightning_chance = 0 })
    wa.world.view = function() return { cx = 500, cy = sky.RAIN_TOP + 100, w = 1000, h = 900, zoom = 1 } end
    frames(3)
    local above, faded_in = 0, 0
    for _, q in ipairs(M.quad_boxes) do
      if q.sprite == "sprites/rain.png" then
        local line = q.depth == wa.depth.FRONT and sky.RAIN_TOP_FRONT or sky.RAIN_TOP
        if q.top < line - 0.01 then above = above + 1 end
      end
    end
    for _, q in ipairs(M.quad) do
      if q.sprite == "sprites/rain.png" and q.uv and q.uv[2] > 0 then faded_in = faded_in + 1 end
    end
    if clouds_on > 0 then
      check("no rain above the clouds' line", above == 0, above)
      check("the cells across it start at the line, cut by uv", faded_in > 0 and (M.fades_in or 0) > 0, faded_in)
    else
      check("without clouds the rain falls from the whole sky", above > 0, above)
    end
  end
  new_match({ darkness = 0, lightning_chance = 0 })
  wa.world.view = function() return { cx = 500, cy = sky.RAIN_TOP, w = 1000, h = 600, zoom = 1 } end
  frames(2)
  local cloud_depth, far_rain = nil, nil
  for _, q in ipairs(M.quads) do
    if q.sprite == "wf-lib/px/sprites/lightning/cloud.png" and q.count > 0 then cloud_depth = cloud_depth or q.depth end
    if q.sprite == "sprites/rain.png" and q.depth >= wa.depth.BEHIND_TERRAIN then
      far_rain = math.min(far_rain or math.huge, q.depth)
    end
  end
  check("the clouds draw nearer than the rain behind the land, hiding where it starts",
    cloud_depth and far_rain and cloud_depth < far_rain, tostring(cloud_depth) .. "," .. tostring(far_rain))
end

print("snow: where it draws")
do
  local sky = load_module("lib/sky")
  new_match(false, { snow = {} })
  frames(3)
  local total, front, below = 0, 0, 0
  for _, q in ipairs(M.quads) do
    if q.sprite == "sprites/flake.png" then
      total = total + q.count
      if q.depth < wa.depth.BEHIND_TERRAIN then front = front + q.count end
    end
  end
  for _, q in ipairs(M.quad_boxes) do
    if q.sprite == "sprites/flake.png" and (q.top + q.bottom) / 2 > 560 then below = below + 1 end
  end
  check("snow falls", total > 50, total)
  check("all of it behind the land", front == 0, front)
  check("none under the water", below == 0, below)
  check("the blizzard sound loops", M.ambients["sounds/blizzard.wav"] ~= nil and M.ambients["sounds/rain.wav"] == nil)
  local cloud
  for _, q in ipairs(M.quads) do
    if q.sprite == "wf-lib/px/sprites/lightning/cloud.png" and q.count > 0 then cloud = cloud or q.colour end
  end
  -- The view at the band, to see the clouds' colour.
  wa.world.view = function() return { cx = 500, cy = sky.RAIN_TOP, w = 1000, h = 600, zoom = 1 } end
  draw()
  for _, q in ipairs(M.quads) do
    if q.sprite == "wf-lib/px/sprites/lightning/cloud.png" and q.count > 0 then cloud = cloud or q.colour end
  end
  check("white clouds", cloud and (cloud >> 16) & 0xff > 200 and cloud & 0xff > 200, cloud and string.format("%08x", cloud))
  local above, cut_in = 0, 0
  wa.world.view = function() return { cx = 500, cy = sky.RAIN_TOP + 100, w = 1000, h = 900, zoom = 1 } end
  draw()
  for _, q in ipairs(M.quad_boxes) do
    if q.sprite == "sprites/flake.png" and (q.top + q.bottom) / 2 < sky.RAIN_TOP then above = above + 1 end
  end
  check("no snow above the clouds' line", above == 0, above)

  wa.world.view = function() return { cx = 1000, cy = 300, w = 1000, h = 600, zoom = 0.2 } end
  draw()
  total = 0
  for _, q in ipairs(M.quads) do
    if q.sprite == "sprites/flake.png" then total = total + q.count end
  end
  check("zoomed far out the flakes stay within the budget", total > 100 and total <= 1000, total)

  new_match(false, { snow = { snow = 0, clouds = 0 } })
  frames(3)
  check("0 % draws no snow and plays no sound", #M.quads == 0 and M.ambients["sounds/blizzard.wav"] == nil)
end

print("snow: settling on open ground")
local function ground(x, y)
  if x >= 800 and x < 900 and y >= 300 and y <= 310 then return true end -- a roof over open ground
  return y >= 400
end
local function settling(snow_options, extra, land_shape)
  extra = extra or {}
  extra.snow = snow_options
  new_match(false, extra)
  local land = pixel_land(land_shape or ground)
  wa.world.wind = function() return 0 end
  return land
end
do
  local land = settling({ settle = true, snow = 100 })
  turn(1)
  check("one clock for the weather", #M.spawned == 1)
  sim_frames(3000)
  local cols, deepest = land.columns()
  local in_ground, under_roof, colour, covered = 0, 0, true, 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    if ground(x, y) then in_ground = in_ground + 1 end
    -- Snow sliding off the roof drifts at its foot, a few pixels in under its edge.
    if x >= 812 and x < 888 and y > 310 then under_roof = under_roof + 1 end
  end
  for x = 0, 1999 do if cols[x] then covered = covered + 1 end end
  for _, t in ipairs(M.stamps) do
    colour = colour and type(t.true_colour) == "table" and t.true_colour.blend > 0 and t.true_colour.blend < 1
  end
  check("snow settles over most of the ground", covered > 1500, covered)
  check("only into the air above the land", in_ground == 0, in_ground)
  check("none stands on air", land.floating() == 0, land.floating())
  check("none under the roof", under_roof == 0, under_roof)
  check("never deeper than the setting", deepest <= 10, deepest)
  check("stamped in its own colours, blended a little with the ground", colour)
  local first = {}
  for i, t in ipairs(M.stamps) do first[i] = t.x .. "," .. t.y .. "," .. t.frame end

  settling({ settle = true, snow = 100 })
  turn(1)
  sim_frames(3000)
  local same = #M.stamps == #first
  for i, t in ipairs(M.stamps) do same = same and first[i] == t.x .. "," .. t.y .. "," .. t.frame end
  check("the same match settles the same snow", same)

  land = settling({ settle = true, snow = 100 })
  M.worms = { { x = 500, y = 395, team = 1, hp = 100 } }
  turn(1)
  sim_frames(3000)
  local near = 0
  for k in pairs(land.added) do
    if math.abs(k % 100000 - 500) < 10 then near = near + 1 end
  end
  check("none grows into a worm", near == 0, near)

  settling({ settle = false })
  turn(1)
  sim_frames(500)
  check("off: no snow settles, no clock", #M.stamps == 0 and #M.spawned == 0)

  -- Grass: bumps of one to three pixels and single-pixel spikes.
  local BUMPS = { 0, 2, 3, 1, 0, 3, 2 }
  local function grass(x, y)
    if x % 23 == 0 and y >= 394 then return true end
    return y >= 400 + BUMPS[x % 7 + 1]
  end
  land = settling({ settle = true, snow = 100 }, nil, grass)
  turn(1)
  sim_frames(3000)
  local on_spikes = 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    if x % 23 == 0 and y < 394 then on_spikes = on_spikes + 1 end
  end
  check("on bumpy grass none stands on air", land.count() > 1000 and land.floating() == 0, land.floating())
  check("it slides off single-pixel spikes", on_spikes == 0, on_spikes)
  -- A blanket, not ice spikes: no column of 2 pixels of snow or more stands 2 pixels over both of its neighbours.
  local cols = land.columns()
  local function top(x)
    for y = 300, 420 do if land.solid(x, y) then return y end end
    return 420
  end
  local spikes = 0
  for x = 1, 1998 do
    local t = top(x)
    if (cols[x] or 0) >= 2 and top(x - 1) - t >= 2 and top(x + 1) - t >= 2 then spikes = spikes + 1 end
  end
  check("it lies as a blanket, without spikes", spikes == 0, spikes)

  -- A round knoll: the snow follows its curve as a layer, with no blocks on the ledges of its steep sides.
  land = settling({ settle = true, snow = 100 }, nil, function(x, y)
    local dx = x - 1000
    if math.abs(dx) < 70 then return y >= 330 + math.floor(70 - math.sqrt(70 * 70 - dx * dx)) end
    return y >= 400
  end)
  turn(1)
  sim_frames(6000)
  local cols = land.columns()
  local covered, blocks = 0, 0
  for x = 960, 1040 do if cols[x] then covered = covered + 1 end end
  -- A block: a column with 3 pixels of snow or more over both of its neighbours.
  for x = 925, 1075 do
    local d = cols[x] or 0
    if d - (cols[x - 1] or 0) >= 3 and d - (cols[x + 1] or 0) >= 3 then blocks = blocks + 1 end
  end
  check("on a round knoll the snow covers its top", covered >= 75, covered)
  check("and builds no blocks on its sides", blocks == 0, blocks)

  -- A steep slope of steps 2 and 3 pixels high in turn: no column of snow stands up over both of its neighbours.
  land = settling({ settle = true, snow = 100 }, nil, function(x, y)
    if x >= 1400 and x < 1440 then
      local k = x - 1400
      return y >= 300 + 2 * k + k // 2
    end
    return y >= (x < 1400 and 300 or 400)
  end)
  turn(1)
  sim_frames(6000)
  local function top(x)
    for y = 250, 420 do if land.solid(x, y) then return y end end
    return 420
  end
  local pillars = 0
  for x = 1395, 1445 do
    local t = top(x)
    if land.added[t * 100000 + x] and top(x - 1) - t >= 2 and top(x + 1) - t >= 2 then pillars = pillars + 1 end
  end
  check("on a steep staircase no snow stands up in pillars", pillars == 0, pillars)

  -- A slope rising three pixels a column: the snow slides down it to the foot.
  land = settling({ settle = true, snow = 100 }, nil, function(x, y)
    if x >= 1500 and x < 1530 then return y >= 400 - 3 * (x - 1499) end
    return y >= 400
  end)
  turn(1)
  sim_frames(3000)
  local on_slope, foot = 0, 0
  for k in pairs(land.added) do
    local x = k % 100000
    -- The drift at the foot banks up the lowest columns of the slope.
    if x >= 1510 and x < 1529 then on_slope = on_slope + 1 end
    if x >= 1496 and x < 1500 then foot = foot + 1 end
  end
  check("none holds on a steep slope; it drifts at the foot", on_slope == 0 and foot >= 10, on_slope .. "," .. foot)

  -- A crater under deep snow: the snow starts again at its floor.
  land = settling({ settle = true, snow = 100, settle_depth = 4 })
  turn(1)
  sim_frames(2000)
  for x = 300, 339 do
    for y = 380, 449 do
      land.removed[y * 100000 + x] = true
      land.added[y * 100000 + x] = nil
    end
  end
  sim_frames(4000)
  local in_crater = 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    if x >= 300 and x < 340 and y > 420 then in_crater = in_crater + 1 end
  end
  check("snow settles again in a crater", in_crater > 0, in_crater)

  -- A ledge under snow blown away: its snow falls to the ground below.
  local function ledge(x, y) return y >= 400 or (x >= 1200 and x < 1300 and y >= 300 and y < 310) end
  land = settling({ settle = true, snow = 100 }, nil, ledge)
  turn(1)
  sim_frames(3000)
  local on_ledge = 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    if x >= 1200 and x < 1300 and y < 300 then on_ledge = on_ledge + 1 end
  end
  -- The snow stops falling while the ledge goes, so what lands below is the snow that fell.
  load_module("lib/weather").target.snow = 0
  for x = 1200, 1299 do
    for y = 300, 309 do land.removed[y * 100000 + x] = true end
  end
  local below_before = 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    if x >= 1200 and x < 1300 and y > 350 then below_before = below_before + 1 end
  end
  sim_frames(200)
  local up, below = 0, 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    if x >= 1200 and x < 1300 and y < 310 then up = up + 1 end
    if x >= 1200 and x < 1300 and y > 350 then below = below + 1 end
  end
  check("snow lay on the ledge", on_ledge > 100, on_ledge)
  check("with the ledge gone none hangs where it was", up == 0, up)
  check("most of it fell to the ground under it", below - below_before >= on_ledge * 0.8,
    below_before .. " + " .. on_ledge .. " -> " .. below)
  check("and stands on it", land.floating() == 0, land.floating())
  -- It settles again a pixel at a time: no column of it stands up over both of its neighbours.
  local function top(x)
    for y = 250, 420 do if land.solid(x, y) then return y end end
    return 420
  end
  local pillars = 0
  for x = 1195, 1305 do
    local t = top(x)
    if land.added[t * 100000 + x] and top(x - 1) - t >= 2 and top(x + 1) - t >= 2 then pillars = pillars + 1 end
  end
  check("and builds no pillars where it lands", pillars == 0, pillars)

  -- A column of snow left in the air over a steep staircase: it settles again a pixel at a time, as no pillar.
  local function stairs(x, y)
    if x >= 1400 and x < 1440 then local k = x - 1400; return y >= 300 + 2 * k + k // 2 end
    return y >= (x < 1400 and 300 or 400)
  end
  land = settling({ settle = true, snow = 100 }, nil, stairs)
  turn(1)
  load_module("lib/weather").target.snow = 0
  sim_frames(1)
  local st8 = load_module("lib/settle").state
  for y = 250, 257 do land.added[y * 100000 + 1420] = true end
  st8.cols[1420] = { top = 250, depth = 8 }
  st8.order[#st8.order + 1] = 1420
  load_module("lib/settle").check(st8, 1420, 560)
  local function stair_top(x)
    for y = 250, 420 do if land.solid(x, y) then return y end end
    return 420
  end
  local fallen_pillars, in_air = 0, 0
  for x = 1395, 1445 do
    local t = stair_top(x)
    if land.added[t * 100000 + x] and stair_top(x - 1) - t >= 2 and stair_top(x + 1) - t >= 2 then
      fallen_pillars = fallen_pillars + 1
    end
  end
  for y = 250, 257 do if land.added[y * 100000 + 1420] then in_air = in_air + 1 end end
  check("snow falling onto a steep face settles without pillars", in_air == 0 and fallen_pillars == 0,
    in_air .. "," .. fallen_pillars)

  -- A cave open to the wind: however hard it blows, no snow settles under its roof.
  land = settling({ settle = true, snow = 100 }, nil, function(x, y)
    if x >= 600 and x < 900 and y >= 250 and y < 300 then return true end -- the roof, open on its right
    if x >= 590 and x < 600 and y >= 250 then return true end -- the back wall
    return y >= 400
  end)
  wa.world.wind = function() return -0.4 end
  turn(1)
  sim_frames(6000)
  local in_cave = 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    -- The mouth's edge: flakes slanting 0.7 a pixel reach under it as far as that from the open side.
    if x >= 600 and x < 830 and y > 300 then in_cave = in_cave + 1 end
  end
  check("strong wind blows no snow deep into a cave", in_cave == 0, in_cave)

  -- The wind blows it onto the side facing it.
  land = settling({ settle = true, snow = 100 }, nil, function(x, y) return y >= 400 or (x >= 1000 and x < 1100 and y >= 200) end)
  wa.world.wind = function() return 0.1 end
  turn(1)
  sim_frames(3000)
  local lee, under_lee = 0, 0
  for k in pairs(land.added) do
    local x, y = k % 100000, k // 100000
    -- Settling flakes slant at most 0.7 pixels across a pixel down: the lee reaches 140 pixels past the
    -- tower; snow sliding off its top drifts against its foot.
    if x >= 1115 and x < 1235 and y > 380 then under_lee = under_lee + 1 end
    if x >= 1300 then lee = lee + 1 end
  end
  check("downwind of a tower the ground stays bare in its lee", under_lee == 0 and lee > 0, under_lee .. "," .. lee)
end

print("snow: melting at a turn cycle's start")
do
  local land = settling({ settle = true, snow = 100 },
    { cycle = { start = "snow", change_chance = 100, rain_weight = 0, snow_weight = 0, clear_weight = 100, melt = 4 } })
  local W = load_module("lib/weather")
  check("the first weather is the one asked for, before the first turn", W.kind == "snow" and W.target.snow == 1)
  turn(1)
  turn(2)
  sim_frames(3000)
  local before = land.count()
  local _, deep_before = land.columns()
  turn(1)
  check("the weather clears at the turn cycle", W.kind == "clear" and W.target.snow == 0 and W.cycles == 1)
  local s = load_module("lib/settle").state
  local queued = #s.queue
  M.cuts = {}
  sim_frames(1)
  check("a big melt is spread over frames", queued > 40 and #M.cuts == 40, queued .. "," .. #M.cuts)
  sim_frames(100)
  local _, deep_after = land.columns()
  check("the top of every pile melts", land.count() < before and deep_after <= deep_before - 3,
    deep_before .. " -> " .. deep_after)
  for _ = 1, 6 do
    turn(2)
    turn(1)
    sim_frames(100)
  end
  local ground_cut = 0
  for k in pairs(land.removed) do
    if ground(k % 100000, k // 100000) then ground_cut = ground_cut + 1 end
  end
  check("cycle by cycle it all melts", land.count() == 0, land.count())
  check("and the ground under it stays whole", ground_cut == 0, ground_cut)
  check("no snow settles while it's clear", W.target.snow == 0)
end

print("the weather cycle")
do
  new_match(false, { snow = {} })
  local W = load_module("lib/weather")
  turn(1); turn(2)
  check("no cycle on the first round", W.cycles == 0)
  turn(1, false)
  check("a team playing again starts the next", W.cycles == 1)
  turn(1)
  check("a worm switch in the turn starts none", W.cycles == 1)
  turn(2); turn(3); turn(1)
  check("a third team joins the round", W.cycles == 2)
  turn(2); turn(1)
  check("a team out of the match leaves it", W.cycles == 3)

  local function run(cycle)
    new_match({ lightning_chance = 0 }, { snow = {}, cycle = cycle })
    local W2 = load_module("lib/weather")
    local kinds = {}
    turn(1)
    kinds[1] = W2.kind
    for i = 2, 12 do
      turn(2); turn(1)
      kinds[i] = W2.kind
    end
    return table.concat(kinds, ",")
  end
  local a = run({ change_chance = 100, clear_weight = 0 })
  check("every cycle changes between the two", not a:find("clear") and not a:find("rain,rain") and not a:find("snow,snow"), a)
  check("the same match gives the same weather", run({ change_chance = 100, clear_weight = 0 }) == a)
  local b = run({ change_chance = 100, snow_weight = 0 })
  check("a kind with no share never comes", not b:find("snow"), b)
  local c = run({ change_chance = 0, start = "rain" })
  check("0 %: the first weather stays", c == string.rep("rain", 12, ","), c)

  new_match({ lightning_chance = 0 }, { cycle = { start = "rain", change_chance = 100, clear_weight = 0, snow_weight = 0 } })
  check("rain alone with no other share stays rain", (function() turn(1); turn(2); turn(1); return load_module("lib/weather").kind end)() == "rain")

  -- On screen the change fades: the rain thins out while the snow comes in.
  new_match({}, { snow = {}, cycle = { start = "rain", change_chance = 100, clear_weight = 0 } })
  W = load_module("lib/weather")
  turn(1); turn(2)
  frames(5)
  local function alpha_of(sprite)
    local top = 0
    for _, q in ipairs(M.quads) do
      if q.sprite == sprite and q.colour then top = math.max(top, q.colour >> 24) end
    end
    return top
  end
  local rain_full = alpha_of("sprites/rain.png")
  turn(1)
  check("the cycle turns to snow", W.kind == "snow")
  frames(60)
  local rain_mid, snow_mid = alpha_of("sprites/rain.png"), alpha_of("sprites/flake.png")
  frames(120)
  check("the rain fades out", rain_full > 0 and rain_mid < rain_full and alpha_of("sprites/rain.png") == 0,
    rain_full .. "," .. rain_mid)
  check("the snow fades in", snow_mid > 0 and alpha_of("sprites/flake.png") > snow_mid)
  check("the rain sound goes quiet, the blizzard comes up",
    M.ambients["sounds/rain.wav"].volume == 0 and M.ambients["sounds/blizzard.wav"].volume > 0)

  -- Lightning only while it rains.
  new_match({ lightning_chance = 100 }, { snow = {}, cycle = { start = "snow", change_chance = 0 } })
  turn(1)
  frames(300)
  check("no lightning in the snow", #M.sounds == 0, #M.sounds)

  -- The cycle alone brings rain and snow with their add-ons' defaults.
  new_match(false, { cycle = { start = "rain", change_chance = 100, clear_weight = 0 } })
  W = load_module("lib/weather")
  frames(3)
  check("the cycle alone starts with the rain asked for", W.kind == "rain" and W.target.rain == 1)
  local rain_drawn = 0
  for _, q in ipairs(M.quads) do if q.sprite == "sprites/rain.png" then rain_drawn = rain_drawn + q.count end end
  check("and draws it", rain_drawn > 0, rain_drawn)
  turn(1); turn(2); turn(1)
  check("and turns to snow", W.kind == "snow" and W.target.snow == 1)
  frames(200)
  local flakes = 0
  for _, q in ipairs(M.quads) do if q.sprite == "sprites/flake.png" then flakes = flakes + q.count end end
  check("and draws that", flakes > 0, flakes)

  -- Those defaults are the add-ons' own, as mod.toml declares them.
  local toml = io.open(ROOT .. "weather/mod.toml"):read("a")
  local declared, component, key = {}, nil, nil
  for line in toml:gmatch("[^\n]+") do
    local id = line:match('^id = "([^"]+)"')
    if id then component = id end
    local k = line:match('^key = "([^"]+)"')
    if k then key = k end
    local v = line:match("^default = (.+)$")
    if v and key then
      declared[component] = declared[component] or {}
      declared[component][key] = v == "true" or (v ~= "false" and (tonumber(v) or v:match('^"(.*)"$')))
      key = nil
    end
  end
  local settings = load_module("lib/settings")
  for kind, id in pairs({ rain = "core.weather", snow = "core.snow" }) do
    local same = true
    for k, v in pairs(declared[id]) do same = same and settings.DEFAULTS[kind][k] == v end
    for k in pairs(settings.DEFAULTS[kind]) do same = same and declared[id][k] ~= nil end
    check("the cycle's " .. kind .. " has the defaults mod.toml gives " .. id, same)
  end
end

print(failed == 0 and "\nALL PASS" or ("\n" .. failed .. " FAILED"))
os.exit(failed == 0 and 0 or 1)
