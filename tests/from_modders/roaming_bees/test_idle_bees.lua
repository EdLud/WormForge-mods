-- Plain Lua harness for lib/bee.lua's idle bees. Run from anywhere:
--   lua tests/from_modders/roaming_bees/test_idle_bees.lua
-- A roaming bee with no worm near sleeps two frames after each think (the
-- engine's `a:sleep`, emulated below); a worm coming near, or a hit, wakes it
-- on the next frame.
local PACK_ROOT = (arg[0]:match("^(.*[/\\])") or "") .. "../../../from_modders/roaming_bees/"

local frame = 0
local actors, worms = {}, {}
local wa = {
  random = function(lo) return lo end,
  math = { cos = math.cos, sin = math.sin, atan = function(y, x) return math.atan(y, x or 1) end },
  log = function() end,
  sound = { play = function() end },
  world = {
    frame = function() return frame end,
    water = function() return 10000 end,
    size = function() return { w = 4000, h = 2000 } end,
  },
  land = { trace = function() return nil end, solid = function() return false end },
  worms = { all = function() return worms end },
  actors = {
    all = function() return actors end,
    -- An actor stands where it was put: WA's movement isn't modelled, only
    -- what the brain asks of it. `thinks` counts whole thinks (each reads
    -- whether the bee is in water once).
    spawn = function(spec)
      local a = { id = #actors + 1, x = spec.x, y = spec.y, vx = spec.vx, vy = spec.vy,
        facing = 1, on = spec.on, thinks = 0 }
      function a:fits() return true end
      function a:in_water() self.thinks = self.thinks + 1; return false end
      function a:gfx() end
      function a:frame() end
      function a:sleep(n, opts) self.asleep, self.near = n, opts and opts.near end
      actors[#actors + 1] = a
      return a
    end,
  },
}
local env = setmetatable({ wa = wa }, { __index = _G })
env.require = function(name) return assert(loadfile(PACK_ROOT .. name .. ".lua", "t", env))() end
local bee = env.require("lib/bee")

local worm = { id = 1, kind = "worm", team = 0, hp = 100, x = 3000, y = 500, vx = 0, vy = 0,
  state = "idle", taken = false }
worms[1] = worm

-- The engine's tick: a sleeping actor's frame call is skipped unless a living
-- worm is within `near`; the call that ends a sleep gets `ev.slept`.
local function step(n)
  for _ = 1, n do
    frame = frame + 1
    for _, a in ipairs(actors) do
      local woke = false
      for _, w in ipairs(worms) do
        if (a.asleep or 0) > 0 and w.hp > 0 and (w.x - a.x) ^ 2 + (w.y - a.y) ^ 2 <= a.near ^ 2 then woke = true end
      end
      if (a.asleep or 0) > 0 and not woke then
        a.asleep, a.slept = a.asleep - 1, (a.slept or 0) + 1
      else
        a.asleep, a.calls = 0, (a.calls or 0) + 1
        local slept = a.slept or 0
        a.slept = 0
        a.on.frame(a, { slept = slept })
      end
    end
  end
end
-- As the engine delivers a hit: it ends a sleep.
local function hit(a, ev)
  a.asleep = 0
  a.on.hit(a, ev)
end

local near = assert(bee.spawn_actor({ x = 500, y = 500, owner = worm, rogue = true }))
local far = assert(bee.spawn_actor({ x = 3600, y = 1400, owner = worm, rogue = true }))

-- A new bee tumbles first (it leaves the spawn faster than it flew), then roams.
step(60)
local counted, called = near.thinks, near.calls
step(9)
assert(near.thinks == counted + 3,
  "an idle bee far from worms thinks every third frame, got " .. near.thinks - counted .. " in 9")
assert(near.calls == called + 3, "and the engine calls it only then, got " .. near.calls - called .. " in 9")

-- Right after a think, a worm walks up to the bee: it wakes on the next frame.
repeat local t = near.thinks; step(1) until near.thinks > t
local before = near.thinks
worm.x, worm.vx, worm.state = 600, 1, "walking"
step(1)
assert(near.thinks == before + 1, "a worm coming near wakes the bee")
step(3)
assert(near.thinks == before + 4, "a bee with a target thinks every frame")

-- The other bee is still far from the worm and rests; a hit wakes it.
repeat local t = far.thinks; step(1) until far.thinks > t
local resting = far.thinks
hit(far, { damage = 1, kind = "bullet", vx = 0, vy = 0 })
step(1)
assert(far.thinks == resting + 1, "a hit bee thinks on the next frame")

print("test_idle_bees: ok")
