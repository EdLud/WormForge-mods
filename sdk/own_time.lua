-- A worm's own frames.

local own_time = {}

local ONE = 256
local supported -- this WormForge has worm.time_scale
local carry, counted, count = {}, {}, {} -- by worm id

function own_time.scale(worm)
  if supported == nil then
    supported = pcall(function() return worm.time_scale end)
  end
  if not supported then return 1 end
  return worm.time_scale or 1
end

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
