-- Plain Lua harness for the map swarm's bee count (lib/bee.lua's bees_for_density). Run from anywhere:
--   lua tests/from_modders/roaming_bees/test_bee_density.lua
local PACK_ROOT = (arg[0]:match("^(.*[/\\])") or "") .. "../../../from_modders/roaming_bees/"

local env = setmetatable({ wa = { log = function() end } }, { __index = _G })
env.require = function(name) return assert(loadfile(PACK_ROOT .. name .. ".lua", "t", env))() end
local bee = env.require("lib/bee")
local count = bee.bees_for_density

-- the two maps it was set by, at 100: a normal battle map and a 7680 by 4176 rope race map
assert(count(100, 1920, 696) == 20, count(100, 1920, 696))
assert(count(100, 7680, 4176) == 250, count(100, 7680, 4176))
-- in between, in a straight line by area; a smaller map still gets some
assert(count(100, 2280, 1168) == 30, count(100, 2280, 1168))
assert(count(100, 1024, 440) == 13, count(100, 1024, 440))
-- no more than 250 past the large map
assert(count(100, 24000, 2200) == 250, count(100, 24000, 2200))
-- density scales it, rounded; 0 places none
assert(count(20, 1920, 696) == 4 and count(25, 1920, 696) == 5 and count(10, 1920, 696) == 2)
assert(count(20, 7680, 4176) == 50)
assert(count(0, 7680, 4176) == 0)
-- what wa.world.size gives may be floats
assert(count(100, 1920.0, 696.0) == 20)

print("test_bee_density: ok")
