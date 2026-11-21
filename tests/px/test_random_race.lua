-- From the mods root: lua tests/px/test_random_race.lua
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
local sdk = root .. "../sdk/"
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/own_time"] = function() return dofile(sdk .. "own_time.lua") end

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local logs, hud_draws = {}, {}
local on
local frame, roll, placing = 0, 1, false
local worms = {}
local loaded
wa = {
  msg = { FRAME_FINISH = 1 },
  log = function(s) logs[#logs + 1] = s end,
  random = function(a, b) return math.min(b, math.max(a, roll)) end,
  assets = { load = function(spec) loaded = spec end },
  worms = { all = function() return worms end },
  world = { frame = function() return frame end, placing = function() return placing end },
  hud = { size = function() return 1920, 1080 end, sprite = function(s) hud_draws[#hud_draws + 1] = s end },
  on = {},
}
local function reset_hooks()
  on = { turn_start = {}, turn_end = {}, worm_message = {}, hud = {} }
  for name, list in pairs(on) do wa.on[name] = function(f) list[#list + 1] = f end end
end
local function fire(name, ...) for _, f in ipairs(on[name]) do f(...) end end

-- Ammo rows by group; worms of one team share theirs.
local rows = {}
local function worm(id, team)
  local w = { id = id, team = team, ammo_group = team, hp = 100, turn = false, state = "standing",
    x = 100, y = 100, vx = 0, vy = 0, facing = 1, keys = {} }
  function w:ammo(weapon, spec)
    rows[self.ammo_group] = rows[self.ammo_group] or {}
    if spec == nil then return rows[self.ammo_group][weapon] or 0 end
    rows[self.ammo_group][weapon] = spec.set
  end
  return w
end
local function ammo(team, weapon) return (rows[team] or {})[weapon] or 0 end

local switched = { parkour = {}, suit = {}, anti_fall = {} }
local shared = require("lib/shared")
shared.parkour_on = function(w) switched.parkour[w.id] = true end
shared.swim_suit_on = function(w) switched.suit[w.id] = true end
shared.anti_fall_damage_on = function(w) switched.anti_fall[w.id] = true end

local ALL = {
  ["px.parkour"] = {}, ["px.jump"] = {}, ["stock.low_gravity"] = {}, ["px.anti_fall_damage"] = {},
  ["px.portal_gun"] = {}, ["px.wings"] = {},
  ["px.helicopter"] = {}, ["stock.ninja_rope"] = {}, ["stock.parachute"] = {},
}
local function install(placed)
  reset_hooks()
  rows, hud_draws, frame = {}, {}, 0
  switched = { parkour = {}, suit = {}, anti_fall = {} }
  package.loaded["scheme/random_race"] = nil
  require("scheme/random_race").install({ weapons = placed })
end

local function turn(w)
  for _, o in ipairs(worms) do o.turn = o == w end
  fire("turn_start", { worm = w })
  frame = frame + 1
  fire("worm_message", w, wa.msg.FRAME_FINISH)
end
local function finish() fire("turn_end") end

worms = { worm(17, 1), worm(33, 2), worm(49, 3) }
install(ALL)
check("the five banners load", loaded and #loaded.sprites == 5, loaded and #loaded.sprites)

-- Manual placement: no race, no banner, no weapons.
placing, roll = true, 5
for _, w in ipairs(worms) do turn(w) finish() end
check("placing: no race chosen", #logs == 0, logs[1])
check("placing: no rope given", ammo(1, "stock.ninja_rope") == 0)
hud_draws = {}
fire("hud")
check("placing: no banner", #hud_draws == 0)

-- The first turn after placement: the rope race, rope and parachute for every team.
placing = false
turn(worms[1])
check("rope race: rope for team 1", ammo(1, "stock.ninja_rope") == -1)
check("rope race: parachute for team 3", ammo(3, "stock.parachute") == -1)
check("rope race: no wings, no jump", ammo(2, "px.wings") == 0 and ammo(2, "px.jump") == 0)
check("rope race: no anti fall damage", ammo(1, "px.anti_fall_damage") == 0 and not switched.anti_fall[17])
hud_draws = {}
fire("hud")
check("the banner shows once the round starts", #hud_draws == 1 and hud_draws[1].sprite:find("rope_race") ~= nil)
frame = frame + 300
hud_draws = {}
fire("hud")
check("the banner is gone after its fade", #hud_draws == 0)
-- A worm switch within the turn chooses nothing new.
roll = 1
fire("turn_start", { worm = worms[1] })
fire("worm_message", worms[1], wa.msg.FRAME_FINISH)
check("a worm switch keeps the race", ammo(1, "stock.ninja_rope") == -1)
finish()
turn(worms[2]) finish()
turn(worms[3]) finish()
check("the other teams keep the race", ammo(3, "stock.ninja_rope") == -1 and ammo(3, "px.parkour") == 0)

-- Team 1 again: a new race. Parkour, with Anti Fall Damage, the suit and air control switched on.
turn(worms[1])
check("parkour race: Parkour and Anti Fall Damage given", ammo(1, "px.parkour") == -1 and ammo(2, "px.anti_fall_damage") == -1)
check("parkour race: Jump and Low Gravity given", ammo(2, "px.jump") == -1 and ammo(1, "stock.low_gravity") == -1)
check("parkour race: the rope taken", ammo(1, "stock.ninja_rope") == 0 and ammo(3, "stock.parachute") == 0)
check("parkour race: Parkour, suit and Anti Fall Damage on",
  switched.parkour[17] and switched.suit[17] and switched.anti_fall[17])
local w = worms[1]
frame = frame + 1
w.state, w.vx, w.vy, w.keys = "falling", 0, 0, { left = true, up = true }
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("parkour race: arrows steer in the air", math.abs(w.vx + 0.1) < 1e-9 and math.abs(w.vy + 0.1) < 1e-9, w.vx .. " " .. w.vy)
w.state, w.vx, w.vy, w.keys = "standing", 0, 0, {}
finish()
turn(worms[2])
check("parkour race: the next team's worm gets it too", switched.parkour[33] and switched.anti_fall[33])
finish()

-- Team 3 gone; team 1 still leads. Portal: Anti Fall Damage, no parkour.
worms[3].hp = 0
roll = 2
switched = { parkour = {}, suit = {}, anti_fall = {} }
turn(worms[1])
check("portal race: Portal Gun and Anti Fall Damage", ammo(1, "px.portal_gun") == -1 and ammo(1, "px.anti_fall_damage") == -1)
check("portal race: Parkour, Jump and Low Gravity taken",
  ammo(1, "px.parkour") == 0 and ammo(1, "px.jump") == 0 and ammo(1, "stock.low_gravity") == 0)
check("portal race: Anti Fall Damage on, no parkour", switched.anti_fall[17] and not switched.parkour[17])
finish()

-- Team 1 out: the team whose turn it is leads from now on.
worms[1].hp = 0
roll = 3
turn(worms[2])
check("lead gone: the next team's turn chooses", ammo(2, "px.wings") == -1 and ammo(2, "px.portal_gun") == 0)
finish()
roll = 4
turn(worms[2])
check("helicopter race", ammo(2, "px.helicopter") == -1 and ammo(2, "px.wings") == 0)
check("helicopter race: no anti fall damage", ammo(2, "px.anti_fall_damage") == 0)
finish()

-- A race whose weapons aren't all placed is never drawn, and its weapons are left alone.
worms = { worm(17, 1), worm(33, 2) }
install({ ["px.wings"] = {}, ["px.portal_gun"] = {}, ["stock.ninja_rope"] = {} })
roll = 1
turn(worms[1])
check("without Anti Fall Damage or Parachute, only Wings is drawn", ammo(1, "px.wings") == -1)
check("weapons outside the draw are left alone", rows[1]["px.portal_gun"] == nil and rows[1]["stock.ninja_rope"] == nil)

if failed > 0 then
  print(failed .. " Random Race check(s) failed")
  os.exit(1)
end
print("Random Race passed")
