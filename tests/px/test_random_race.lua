-- From the mods root: lua tests/px/test_random_race.lua
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
local sdk = root .. "../sdk/"
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/own_time"] = function() return dofile(sdk .. "own_time.lua") end
package.preload["own_time"] = function() return require("wf-lib/own_time") end
package.preload["wf-lib/parkour"] = function() return dofile(sdk .. "parkour.lua") end

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local selectable, logs, hud_draws = {}, {}, {}
local on = { turn_start = {}, turn_end = {}, worm_message = {}, hud = {} }
local frame, roll = 0, 1
local worms = {}
local loaded
wa = {
  msg = { FRAME_FINISH = 1, JUMP = 2, JUMP_UP = 3 },
  log = function(s) logs[#logs + 1] = s end,
  random = function(a, b) return math.min(b, math.max(a, roll)) end,
  assets = { load = function(spec) loaded = spec end },
  weapons = { set_selectable = function(s) selectable[s.team .. " " .. s.weapon] = s.selectable end },
  worms = { all = function() return worms end },
  world = { frame = function() return frame end },
  land = { trace = function(x1, y1, x2, y2)
    if x2 > x1 then return { hit = true, x = x1 + 5, y = y1 } end
  end },
  hud = { size = function() return 1920, 1080 end, sprite = function(s) hud_draws[#hud_draws + 1] = s end },
  on = {},
}
for name, list in pairs(on) do wa.on[name] = function(f) list[#list + 1] = f end end
local function fire(name, ...)
  local r
  for _, f in ipairs(on[name]) do r = f(...) or r end
  return r
end

local function worm(id, team)
  local w = { id = id, team = team, hp = 100, turn = false, state = "standing", x = 100, y = 100, vx = 0, vy = 0,
    facing = 1, keys = {} }
  function w:jump() self.state = "jumping" end
  return w
end
worms = { worm(17, 1), worm(33, 2), worm(49, 3) }

local suited = {}
require("lib/shared").swim_suit_on = function(w) suited[w.id] = true end

local placed = {
  ["stock.ninja_rope"] = {}, ["px.jump"] = {}, ["stock.low_gravity"] = {}, ["px.wings"] = {},
  ["px.portal_gun"] = {}, ["px.helicopter"] = {},
}
require("scheme/random_race").install({ weapons = placed })
check("the five banners load", loaded and #loaded.sprites == 5, loaded and #loaded.sprites)

local function turn(w)
  for _, o in ipairs(worms) do o.turn = o == w end
  fire("turn_start", { worm = w })
end
local function finish() fire("turn_end") end

-- Rope race: only the rope for every team, for one turn each of the three teams.
roll = 1
turn(worms[1])
check("rope race: rope selectable", selectable["1 stock.ninja_rope"] == true)
check("rope race: wings locked for team 6 too", selectable["6 px.wings"] == false)
check("rope race: Jump and Low Gravity locked", selectable["2 px.jump"] == false and selectable["2 stock.low_gravity"] == false)
check("rope race: no swim suit", not suited[17])
check("the banner shows", (function() hud_draws = {}; fire("hud"); return #hud_draws == 1 end)())
check("the banner is the rope's", hud_draws[1] and hud_draws[1].sprite:find("rope_race") ~= nil)
frame = 300
hud_draws = {}
fire("hud")
check("the banner is gone after its fade", #hud_draws == 0)
-- A worm switch within the turn draws no new race.
roll = 2
fire("turn_start", { worm = worms[1] })
check("a worm switch keeps the race", selectable["1 stock.ninja_rope"] == true)
finish()
turn(worms[2]) finish()
turn(worms[3]) finish()
check("three turns of the rope race", selectable["3 stock.ninja_rope"] == true)

-- Then a parkour race: Jump and Low Gravity, the suit, wall kicks and air control.
roll = 2
turn(worms[1])
check("parkour race: Jump selectable", selectable["1 px.jump"] == true and selectable["1 stock.low_gravity"] == true)
check("parkour race: rope locked", selectable["1 stock.ninja_rope"] == false)
check("parkour race: the suit goes on", suited[17])
local w = worms[1]
w.state, w.vx, w.vy = "jumping", 0, 1
local eaten = fire("worm_message", w, wa.msg.JUMP)
check("parkour race: Enter in the air is the race's", eaten == "eat")
check("parkour race: the wall kick's strength is 6", w.vy == -6, w.vy)
check("parkour race: kicked off the wall at 5", w.vx == -5, w.vx)
frame = frame + 1
w.state, w.vx, w.vy, w.keys = "falling", 0, 0, { left = true, up = true }
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("parkour race: arrows steer in the air", math.abs(w.vx + 0.1) < 1e-9 and math.abs(w.vy + 0.1) < 1e-9, w.vx .. " " .. w.vy)
w.state, w.vx, w.keys = "standing", 0, { left = true }
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("parkour race: no steering on the ground", w.vx == 0)
finish()

-- A team gone: the next race lasts as many turns as teams are left.
worms[3].hp = 0
turn(worms[2]) finish()
turn(worms[1]) finish()
roll = 5
turn(worms[2])
check("a team out: the race changes after two turns", selectable["2 px.helicopter"] == true, logs[#logs])
check("helicopter race: no parkour", fire("worm_message", worms[2], wa.msg.JUMP) == nil)

-- A race whose weapons aren't all placed is never drawn.
on = { turn_start = {}, turn_end = {}, worm_message = {}, hud = {} }
for name, list in pairs(on) do wa.on[name] = function(f) list[#list + 1] = f end end
selectable = {}
package.loaded["scheme/random_race"] = nil
require("scheme/random_race").install({ weapons = { ["stock.ninja_rope"] = {}, ["px.jump"] = {}, ["px.wings"] = {} } })
roll = 2
turn(worms[1])
check("without Low Gravity, no parkour race: the second race is Wings", selectable["1 px.wings"] == true)
check("Jump is left alone outside the draw", selectable["1 px.jump"] == nil)

if failed > 0 then
  print(failed .. " Random Race check(s) failed")
  os.exit(1)
end
print("Random Race passed")
