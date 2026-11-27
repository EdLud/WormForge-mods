-- From the repository root: lua mods/utilities/test_ex_turn_side.lua
local root = UTILITIES_ROOT or "mods/utilities/"

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local handler, keys
wa = {
  world = { keys = function() return keys end },
  msg = { FRAME_FINISH = 2 },
  on = { worm_message = function(f) handler = f end },
}
dofile(root .. "features/ex_turn_side.lua")

-- A fresh Left press on a right-facing worm in `state`; the facing after it.
local function press_left(state, fired, to_fire)
  local w = { turn = true, facing = 1, state = state, shots_fired = fired or 0, shots_to_fire = to_fire or 0 }
  keys = {}
  handler(w)
  keys = { left = true }
  handler(w)
  return w.facing
end

check("jumping turns", press_left("jumping") == -1)
check("parachuting turns", press_left("parachuting") == -1)
check("torching (Blow Torch) turns", press_left("torching") == -1)
check("charging keeps its side", press_left("charging") == 1)
check("wind-up (Fire Punch, Dragon Ball, Prod) keeps its side", press_left("prefiring") == 1)
check("punching keeps its side", press_left("punching") == 1)
check("repeat fire (Uzi, Flame Thrower, Laser Gun) turns", press_left("firing", 3, 10) == -1)
check("after the last shot keeps its side", press_left("firing", 10, 10) == 1)
check("after a single shot keeps its side", press_left("firing", 0, 0) == 1)

-- Left held through a charge turns nobody once the charge ends.
local w = { turn = true, facing = 1, state = "charging", shots_fired = 0, shots_to_fire = 0 }
keys = {}
handler(w)
keys = { left = true }
handler(w)
w.state = "jumping"
handler(w)
check("a press held through the charge isn't a new press", w.facing == 1)

if failed > 0 then error(failed .. " FAILED") end
print("ExTurnSide: no turning during a charge, a wind-up or a punch; repeat fire still turns: PASS")
