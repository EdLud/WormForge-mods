-- lua mods/tests/px/test_attack_helicopter.lua
-- A round WA refuses (its object pool full) is not a shot: no sound, no
-- casing, no bullet spent, and the next try waits for the shot cadence rather
-- than the next frame. Any other launch error still reaches the brain.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../px/"
package.path = root .. "?.lua;" .. package.path

local POOL_FULL = "runtime error: weapons.launch: WA's object pool is full"
local launch_error, tries, launched, sounds, casings, actors
local function reset()
  launch_error, tries, launched, sounds, casings, actors = nil, 0, 0, {}, 0, {}
end
reset()

local next_id = 0
local function actor(spec)
  next_id = next_id + 1
  local a = { id = next_id, x = spec.x, y = spec.y, on = spec.on }
  function a:frame() end
  function a:gfx() end
  function a:gravity() end
  function a:move() end
  function a:despawn() self.dead = true end
  actors[#actors + 1] = a
  return a
end

local click
wa = {
  depth = { OBJECTS = 0x100 },
  on = { missile_frame = function() end, draw = function() end },
  draw = { ribbon = function() end },
  math = { sin = math.sin, cos = math.cos, atan = function(y, x) return math.atan(y, x) end },
  random = function(lo, hi) return lo end,
  log = function() end,
  world = { size = function() return { w = 2000, h = 1000 } end, water = function() return 900 end },
  worms = { all = function() return {} end },
  land = { trace = function() return nil end },
  actors = {
    spawn = function(spec)
      if spec.kind == "casing" then casings = casings + 1 end
      return actor(spec)
    end,
  },
  sound = { play = function(_, path) sounds[#sounds + 1] = path end },
  weapons = {
    replace = function(spec) click = spec.on_click end,
    launch = function()
      tries = tries + 1
      if launch_error then error(launch_error) end
      launched = launched + 1
      return 1000 + launched
    end,
  },
}

local component = dofile(root .. "weapons/attack_helicopter.lua")
component.install({
  option = function(k) assert(k == "bullets"); return 17 end,
  position = { row = "F6", column = 1 },
})

local function check(what, ok) if not ok then error("FAIL: " .. what, 2) end print("  ok   " .. what) end

-- Strike at (1000, 500); the helicopter enters from the right and opens fire
-- once it is within 450 px and its 40-frame wind-up has run.
local function strike()
  click({ worm = { id = 3, kind = "worm", facing = 1, x = 1000, y = 500 }, x = 1000, y = 500 })
  for _, a in ipairs(actors) do
    if type(a.on) == "table" and a.on.frame then return a end
  end
end
local function run(body, frames)
  for _ = 1, frames do body.on.frame(body) end
end
local function shot_sounds()
  local n = 0
  for _, s in ipairs(sounds) do if s:find("/hks", 1, true) then n = n + 1 end end
  return n
end

print("attack helicopter: a full object pool")
do
  reset()
  launch_error = POOL_FULL
  local body = strike()
  run(body, 200)
  check("it tried to fire", tries > 0)
  check("once per shot cadence (5 frames), not every frame", tries <= 200 / 5)
  check("no shooting sound for a refused round", shot_sounds() == 0)
  check("no casing for a refused round", casings == 0)
  -- The pool frees: all 17 rounds still fly, each with its sound and casing.
  launch_error, tries = nil, 0
  run(body, 200)
  check("the magazine was not spent on refusals: 17 rounds fly", launched == 17)
  check("a sound per round", shot_sounds() == 17)
  check("a casing per round", casings == 17)
end

print("attack helicopter: any other launch error")
do
  reset()
  launch_error = "runtime error: weapons.launch: bad owner"
  local body = strike()
  local ok, err = pcall(run, body, 200)
  check("reaches the brain", not ok and tostring(err):find("bad owner", 1, true) ~= nil)
end

print("ALL PASS")
