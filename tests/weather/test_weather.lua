-- Weather tests: the lightning chance, what strikes, where rain draws and rings stopping at the shore.
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
local function new_match(options)
  modules = {}
  local seed = 12345
  local function next_int()
    seed = (seed * 1103515245 + 12345) % 0x80000000
    return seed
  end
  M = { frame = 0, draws = {}, turn_starts = {}, spawned = {}, quads = {}, quad = {}, quad_boxes = {}, ribbons = {},
    mines = {}, oil = {}, crates = {}, worms = {}, graves = {}, sounds = {} }
  local function solid(x, y) return x < 200 and y >= 400 end
  wa = {
    depth = { BEHIND_TERRAIN = 0x180000, TERRAIN = 0x180000, FRONT = 0x10000 },
    sprites = { key = function(p) return p end },
    msg = {},
    draw = {
      random = function() return next_int() / 0x80000000 end,
      fraction = function() return 0 end,
      quads = function(b)
        M.quads[#M.quads + 1] = { sprite = b.sprite, frame = b.frame, depth = b.depth, count = b.count }
        for i = 0, b.count - 1 do
          local l = b.quads
          M.quad_boxes[#M.quad_boxes + 1] = { sprite = b.sprite, depth = b.depth, top = l[i * 9 + 2], bottom = l[i * 9 + 6], left = l[i * 9 + 1] }
        end
      end,
      quad = function(q)
        M.quad[#M.quad + 1] = { sprite = q.sprite, depth = q.depth, blend = q.blend }
        M.quad_boxes[#M.quad_boxes + 1] = { sprite = q.sprite, top = q.points[1][2], bottom = q.points[3][2] }
        if q.colors and q.colors[3] >> 24 == 0 then M.fades = (M.fades or 0) + 1 end
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
    },
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
      ambient = function(t) M.ambient = t; return {} end,
    },
    actors = {
      spawn = function(spec)
        local a = { x = spec.x, y = spec.y, on = spec.on, owner = spec.owner }
        function a:despawn() self.dead = true end
        M.spawned[#M.spawned + 1] = a
        return a
      end,
    },
    random = function(a, b) return a + next_int() % (b - a + 1) end,
    math = { cos = math.cos, sin = math.sin },
    mines = { all = function() return M.mines end },
    oil = { all = function() return M.oil end },
    crates = { all = function() return M.crates end },
    worms = { all = function() return M.worms end },
    graves = { all = function() return M.graves end },
  }
  local install = load_module("features/weather")
  local values = { rain = 80, wind = 100, clouds = 70, darkness = 25, ripples = true,
    lightning_chance = 100, lightning_effect = "strike", volume = 70 }
  for k, v in pairs(options or {}) do values[k] = v end
  install({ option = function(key) return values[key] end })
end

local function draw()
  M.quads, M.quad, M.quad_boxes, M.ribbons = {}, {}, {}, {}
  for _, f in ipairs(M.draws) do f() end
end

local function frames(n)
  for _ = 1, n do
    M.frame = M.frame + 1
    for _, a in ipairs(M.spawned) do if not a.dead then a.on(a) end end
    draw()
  end
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
  local under, crossing = 0, 0
  for _, q in ipairs(M.quad_boxes) do
    if q.sprite == "sprites/rain.png" then
      if q.top >= 560 then under = under + 1 end
      if q.top < 560 and q.bottom > 560 then crossing = crossing + 1 end
    end
  end
  check("no rain cell under the water line", under == 0, under)
  check("the cells across it fade out", crossing > 0 and M.fades > 0, crossing .. "," .. tostring(M.fades))
  check("the rain sound loops from the start", M.ambient and M.ambient.path == "sounds/rain.wav")
  check("the sheets are loaded with the lightning's",
    M.assets and #M.assets.sprites == 8 and #M.assets.sounds == 3)

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

print(failed == 0 and "\nALL PASS" or ("\n" .. failed .. " FAILED"))
os.exit(failed == 0 and 0 or 1)
