-- From the repository root: lua mods/utilities/test_heal_per_turn.lua
local root = UTILITIES_ROOT or "mods/utilities/"
local starts, ends = {}, {}
local env = setmetatable({}, { __index = _G })
env.wa = {
  msg = { FRAME_FINISH = 2 },
  on = {
    turn_start = function(fn) starts[#starts + 1] = fn end,
    turn_end = function(fn) ends[#ends + 1] = fn end,
  },
  log = function() end,
}
env.require = function(name) return assert(loadfile(root .. name .. ".lua", "t", env))() end
local install = assert(loadfile(root .. "features/utilities.lua", "t", env))()
install{ option = function(key)
  if key == "heal_per_turn" then return 10 end
  return false
end }

local function worm(id)
  local w = { id = id, healed = 0 }
  function w:heal(hp) self.healed = self.healed + hp end
  return w
end
local function fire(list, ev) for _, fn in ipairs(list) do fn(ev) end end
local function start(w) fire(starts, { worm = w, active = w }) end

local first, second, third, other = worm(17), worm(18), worm(19), worm(33)
start(first)
-- Tab, Select Worm or a scheme's worm select: turn_start again, no turn_end.
start(second)
start(third)
assert(first.healed == 10, "the turn's first worm is healed")
assert(second.healed == 0 and third.healed == 0, "a worm switched to within the turn is not")
fire(ends, { worm = third, active = third })
start(other)
assert(other.healed == 10, "the next turn heals its first worm")
-- A turn whose worm is gone (a Kamikaze) ends with no worm.
fire(ends, {})
start(first)
assert(first.healed == 20, "and the turn after that")
print("Heal per turn: the turn's first worm only, not worm switches: PASS")
