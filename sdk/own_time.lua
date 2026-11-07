-- A worm's own frames. A worm on its own time (worm.time_scale, as Bullet
-- Time sets it) lives more or fewer frames than the world: at 2.5 WA steps
-- its body and its frame 2, 3, 2, 3 times a world frame. A pack's hook on
-- its FRAME_FINISH still runs once a world frame, so what the pack does once
-- a frame of the worm's (a push, a damping, a timer) it does
-- own_time.frames(worm) times there; a speed it hands the worm from
-- something on the world's time (a rocket it rides) it divides by
-- own_time.scale(worm).
--
-- The count is the engine's way: the scale in 1/256ths, the fraction carried
-- to the next world frame, worked out once a world frame for each worm (asked
-- again that frame, the same count). Integers only, so every peer counts the
-- same. At scale 1 it is 1, and the carry starts again from 0 the next time
-- the scale changes, as the engine's does.

local own_time = {}

local ONE = 256
local supported -- this WormForge has worm.time_scale
local carry, counted, count = {}, {}, {} -- by worm id

-- The worm's own frames a world frame, as a number (1 at the world's pace).
function own_time.scale(worm)
  if supported == nil then
    supported = pcall(function() return worm.time_scale end)
  end
  if not supported then return 1 end
  return worm.time_scale or 1
end

-- How many of its own frames the worm lives this world frame: an integer.
function own_time.frames(worm)
  local q = math.floor(own_time.scale(worm) * ONE + 0.5)
  local id = worm.id
  if q == ONE then
    if counted[id] ~= nil then carry[id], counted[id], count[id] = nil, nil, nil end
    return 1
  end
  local frame = wa.world.frame()
  if counted[id] ~= frame then
    local total = (carry[id] or 0) + q
    counted[id], count[id], carry[id] = frame, total // ONE, total % ONE
  end
  return count[id]
end

return own_time
