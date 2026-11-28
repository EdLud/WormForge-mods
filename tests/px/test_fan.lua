-- From the mods root: lua tests/px/test_fan.lua
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then print("  ok   " .. name); return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

local actions, providers = {}, {}
package.loaded["lib/turn_controls"] = { register = function(id, callbacks) actions[id] = callbacks end }
package.loaded["lib/electrical"] = { register = function(p) providers[p.kind] = p end }

local on = { frame = {}, turn_start = {}, turn_end = {}, worm_message = {} }
local wind, set_winds = 0.1, 0
local keys = {}
local worms, actors = {}, {}
local explosions, removed, repels = 0, 0, 0
local spawns, clock = {}, 0

local function list(t) return function() local out = {} for _, v in ipairs(t) do out[#out + 1] = v end return out end end
local function empty() return {} end

wa = {
  msg = { FRAME_FINISH = 1 },
  log = function() end,
  random = function(a, b) return (a + b) // 2 end,
  math = { sin = math.sin, cos = math.cos },
  sound = { play = function() end },
  fire = { repel = function() repels = repels + 1 end },
  world = {
    wind = function() return wind end,
    set_wind = function(v) wind = v; set_winds = set_winds + 1 end,
    water = function() return 1000 end,
    gravity = function() return 0.1 end,
    keys = function() return keys end,
    frame = function() return clock end,
  },
  worms = { all = list(worms) },
  actors = {
    all = list(actors),
    spawn = function(spec)
      spawns[#spawns + 1] = spec
      local a = { id = #actors + 100, x = spec.x, y = spec.y, vx = spec.vx, vy = spec.vy, on = spec.on, grab = true }
      function a:fits() return true end
      function a:on_feet() return true end
      function a:warp(t) self.x, self.y, self.vx, self.vy = t.x, t.y, t.vx or self.vx, t.vy or self.vy end
      function a:collision_ignore() return false end
      function a:explode() explosions = explosions + 1 end
      function a:remove() removed = removed + 1 end
      function a:hit(damage, vx, vy, kind)
        self.on.hit(self, { kind = kind or "prod", damage = damage, vx = vx, vy = vy })
        return true
      end
      actors[#actors + 1] = a
      return a
    end,
  },
  missiles = { all = empty }, mines = { all = empty }, oil = { all = empty }, crates = { all = empty },
  on = {},
}
for name, hooks in pairs(on) do wa.on[name] = function(f) hooks[#hooks + 1] = f end end
local function fire(name, ...) for _, f in ipairs(on[name]) do f(...) end end

local shared = require("lib/shared")
shared.fires = {}
local airflow = require("lib/airflow")
local fan = require("weapons/fan")
fan.setup()
local controls = actions["px.fan"]

local function worm(id, team, facing)
  local w = { id = id, team = team, alliance = team - 1, facing = facing, x = 500, y = 600, vx = 0, vy = 0,
    hp = 100, turn = true, weapon = "px.fan", hits = {} }
  function w:hit(t) self.hits[#self.hits + 1] = t end
  worms[#worms + 1] = w
  return w
end
local function frames(n)
  for _ = 1, n do
    clock = clock + 1
    for _, a in ipairs(actors) do a.on.frame(a) end
    fire("frame")
  end
end
local function turn(team) fire("turn_end"); fire("turn_start", { worm = { team = team } }) end

local red, blue = worm(1, 1, 1), worm(2, 2, -1)

print("on its side: the wind")
shared.fires.fan({ worm = red })
local a = actors[1]
check("it stands on its outline's feet, as a sentry", spawns[1].origin == "bottom"
  and spawns[1].body.shape == "sprites/fan/mask_right.png" and spawns[1].gravity == 1)
frames(1)
check("force 5 facing right blows the wind up to the cap", near(wind, 0.34), wind)
wind = -0.2 -- the next turn's wind, rolled after the turn started
turn(2)
frames(1)
check("the fan adds to the turn's new wind", near(wind, -0.2 + 0.35), wind)
turn(1); frames(1)
turn(2); frames(1)
check("still blowing through its owner's first turn", near(wind, -0.2 + 0.35), wind)
turn(1); frames(1)
check("after 7 - force owner turns it stops and the wind is the turn's own", near(wind, -0.2), wind)
local writes = set_winds
frames(5)
check("a stopped fan leaves the wind alone", set_winds == writes)

print("controls")
controls.choose(blue, 2)
keys = { plus_key = true }
fire("worm_message", blue, wa.msg.FRAME_FINISH)
keys = {}
fire("worm_message", blue, wa.msg.FRAME_FINISH)
check("the hint shows the chosen force and mode", controls.hint(blue):find("force 2, upright") ~= nil, controls.hint(blue))
controls.choose(blue, 9)
check("digits past 5 are force 5", controls.hint(blue):find("force 5") ~= nil)
controls.choose(blue, 3)

print("upright: rising air")
blue.x = 800
shared.fires.fan({ worm = blue })
local v = actors[2]
wind = 0.05
frames(1)
check("an upright fan leaves the wind alone", near(wind, 0.05), wind)
check("lift right above it", airflow.lift(v.x, v.y - 40) > 0.5)
check("less lift higher up", airflow.lift(v.x, v.y - 150) < airflow.lift(v.x, v.y - 40))
check("no lift beyond 3 * 64 px", airflow.lift(v.x, v.y - 3 * 64 - 20) == 0)
check("no lift beside the column", airflow.lift(v.x + 20, v.y - 40) == 0)
check("flames are pushed every frame", repels > 0)

print("damage and the grate")
v.on.hit(v, { kind = "blast", damage = 8 })
check("a small blast leaves the grate", providers.fan.targets()[1] ~= nil)
local before = #blue.hits
blue.x, blue.y = v.x, v.y - 20
frames(40)
check("the grate keeps the blades off", #blue.hits == before)
v.on.hit(v, { kind = "bullet", damage = 2 })
frames(31)
check("without the grate the blades hit a worm above them", #blue.hits > before, #blue.hits - before)
check("the first blade hit takes 14", blue.hits[before + 1] and blue.hits[before + 1].amount == 14)
frames(6)
check("the next takes 4 less", blue.hits[before + 2] and blue.hits[before + 2].amount == 10)
local health = providers.fan.targets()[1].f.health
check("a Javelin on the fan hits it", shared.fan_hit(v.x, v.y - 10, 20, 77))
check("for 20", providers.fan.targets()[1].f.health == health - 20)
v.vx = 0
v.on.touched(v, { other = { kind = "missile", id = 77 }, vx = 8, vy = 0 })
check("and its touch doesn't push it again", v.vx == 0)
v.on.touched(v, { other = { kind = "worm", id = 2 }, vx = 4, vy = 0 })
check("a worm running into it pushes it with half its speed", v.vx == 2, v.vx)
v.vx = 0

print("the Tazer")
local target = providers.fan.targets()[1]
check("the Tazer targets a running fan", target and target.id == v.id)
providers.fan.zap(target, 1)
local removed_before, explosions_before = removed, explosions
frames(1)
check("a zap destroys it, with its blast", removed == removed_before + 1 and explosions == explosions_before + 1)
check("a destroyed fan lifts nothing", airflow.lift(v.x, v.y - 40) == 0)
check("Javelins no longer find it", not shared.fan_hit(v.x, v.y - 10, 20))

print("airflow")
red.x, red.facing = 300, -1
shared.fires.fan({ worm = red })
local h = actors[#actors]
frames(1)
local px, py = airflow.push(h.x - 40, h.y - 20)
check("a fan facing left pushes what is in front of it left", px < 0 and py == 0, px)
check("and nothing behind it", airflow.push(h.x + 40, h.y - 20) == 0)

print("water")
wind = 0
frames(1)
check("the left-facing fan blows left", near(wind, -0.34), wind)
h.y = 1001
frames(1)
check("in the water it stops blowing", near(wind, 0), wind)
check("and pushes nothing", airflow.push(h.x - 40, h.y - 20) == 0)

if failed > 0 then print(failed .. " FAILED"); os.exit(1) end
print("ALL PASS")
