-- From the mods root: lua tests/px/test_anti_fall_damage.lua
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local actions, sounds = {}, 0
local on = { turn_start = {}, turn_end = {}, worm_message = {} }
-- The real turn controls (its Auto-Use), keeping each weapon's callbacks.
package.loaded["lib/weapon_hint"] = { register = function() end }
wa = {
  msg = { FRAME_FINISH = 1, FIRE_WEAPON = 2 },
  sound = { play = function() sounds = sounds + 1 end },
  world = { keys = function() return {} end },
  on = {},
}
local turn_controls = require("lib/turn_controls")
local register = turn_controls.register
turn_controls.register = function(id, callbacks) actions[id] = callbacks; register(id, callbacks) end
for name, list in pairs(on) do wa.on[name] = function(f) list[#list + 1] = f end end
local function fire(name, ...) for _, f in ipairs(on[name]) do f(...) end end

local function worm()
  local w = { id = 17, turn = true, state = "jumping", vx = 0, vy = 0, units = 0, states = {} }
  function w:set_state(s) self.state = s; self.states[#self.states + 1] = s end
  function w:ammo(_, n)
    if n == nil then return self.units end
    if self.units ~= -1 then self.units = self.units + n end
  end
  return w
end

local afd = require("weapons/anti_fall_damage")
afd.setup()
turn_controls.setup()
local controls = actions["px.anti_fall_damage"]

-- Off: a fast fall stays WA's.
local w = worm()
w.state, w.vy = "tumbling", 12
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("off: the tumble is left alone", w.state == "tumbling")

-- Fired by hand: on for the turn, with its sound.
controls.fire(w)
check("firing plays the sound", sounds == 1)
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("on: a tumble faster than 8 becomes a fall", w.state == "falling")
w.state, w.vx, w.vy = "blasted", -9, 0
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("on: a blast sideways faster than 8 too", w.state == "falling")
w.state, w.vy = "jumping", 20
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("a fast jump already lands softly: left alone", w.state == "jumping")
w.state, w.vx, w.vy = "after_rope", 3, 8
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("8 itself is not faster than 8", w.state == "after_rope")
w.state, w.vy = "roping", 20
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("the rope is left alone", w.state == "roping")
w.state, w.vy, w.turn = "hit", 20, false
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("a worm without the turn is left alone", w.state == "hit")
w.turn = true
controls.fire(w)
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("fired again: off", w.state == "hit")
controls.fire(w)
controls.finish()
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("the turn's end switches it off", w.state == "hit")

-- Auto-Use: on at turn start while there is ammo, a unit spent.
afd.configure({ data = { instant_use = "auto_use", auto_use = true } })
w = worm()
w.units = 1
fire("turn_start", { worm = w })
w.state, w.vy = "tumbling", 10
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("auto-use: on at turn start", w.state == "falling")
check("auto-use: a unit spent", w.units == 0, w.units)
fire("turn_start", { worm = w })
check("a worm switch keeps it on", w.units == 0)
controls.finish()
fire("turn_start", { worm = w })
w.state = "tumbling"
fire("worm_message", w, wa.msg.FRAME_FINISH)
check("auto-use: none left, off", w.state == "tumbling")
w.units = -1
controls.finish()
fire("turn_start", { worm = w })
check("auto-use: infinite stays infinite", w.units == -1)

if failed > 0 then
  print(failed .. " Anti Fall Damage check(s) failed")
  os.exit(1)
end
print("Anti Fall Damage passed")
