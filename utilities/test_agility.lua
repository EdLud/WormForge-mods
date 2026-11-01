-- From the repository root: lua mods/utilities/test_agility.lua
local root = UTILITIES_ROOT or "mods/utilities/"

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local handler, gravity
local function setup()
  gravity = 0.24
  wa = {
    world = { gravity = function() return gravity end },
    msg = { FRAME_FINISH = 2 },
    on = { worm_message = function(f) handler = f end },
  }
  dofile(root .. "features/agility.lua")
end

local function worm(keys)
  return { turn = true, state_id = 0x79, vx = 0, vy = 0, gravity = 1, keys = keys }
end

local function close(a, b) return math.abs(a - b) < 1e-9 end

-- The match's gravity: the full nudge up.
setup()
local w = worm({ up = true })
handler(w)
check("up at the match's gravity", close(w.vy, -0.1), w.vy)

-- Gravity Control's Very Low Gravity lowers the world's gravity, not the
-- worm's: the small nudge, which stays under it.
gravity = 0.24 * 0.3
w = worm({ up = true })
handler(w)
check("up under Very Low Gravity", close(w.vy, -0.03), w.vy)
check("under Very Low Gravity the worm still falls", 0.03 < gravity)

-- High gravity too, as PX (ModulatedGravity ~= 1).
gravity = 0.24 * 1.7
w = worm({ up = true })
handler(w)
check("up under High Gravity", close(w.vy, -0.03), w.vy)

-- Back to the match's: the full nudge again; the other keys never change.
gravity = 0.24
w = worm({ up = true, left = true })
handler(w)
check("up after Gravity Control ends", close(w.vy, -0.1) and close(w.vx, -0.1), w.vx .. "," .. w.vy)
gravity = 0.24 * 0.3
w = worm({ down = true, right = true })
handler(w)
check("down and right whatever the gravity", close(w.vy, 0.1) and close(w.vx, 0.1), w.vx .. "," .. w.vy)

-- Only the turn's worm, only in the air states.
w = worm({ up = true })
w.turn = false
handler(w)
check("only the turn's worm", w.vy == 0)
w = worm({ up = true })
w.state_id = 0x65
handler(w)
check("not standing", w.vy == 0)

if failed > 0 then error(failed .. " FAILED") end
print("Agility: the up nudge follows the world's gravity, as PX's ModulatedGravity: PASS")
