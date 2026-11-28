-- The air the Fans blow: a column along each running fan's airflow. Upright
-- fans lift the pack vehicles where their worm is (the Hang-Glider and the
-- Hot Air Balloon); every running fan pushes bowling balls along its flow.

local airflow = {}

local sources = {}

-- `source` holds x, y (the column's foot, pixels), dx, dy (the way it blows:
-- 1, 0 or -1 on each axis), reach (its length), half_width, power (the push
-- at the foot, pixels/frame²) and on.
function airflow.add(source)
  sources[#sources + 1] = source
  return source
end

function airflow.remove(source)
  for i, s in ipairs(sources) do
    if s == source then table.remove(sources, i); return end
  end
end

-- The push of one column at (x, y): full at its foot, fading with the
-- square of the distance to nothing at its reach.
local function strength(s, x, y)
  if not s.on then return 0 end
  local ox, oy = x - s.x, y - s.y
  local along = ox * s.dx + oy * s.dy
  local across = ox * s.dy - oy * s.dx
  if along <= 0 or across <= -s.half_width or across >= s.half_width then return 0 end
  local d = math.min(1, along / s.reach)
  return s.power * (1 - d * d)
end

-- The upward push at (x, y), pixels/frame², from the upright fans only.
function airflow.lift(x, y)
  local lift = 0
  for _, s in ipairs(sources) do
    if s.dy < 0 then lift = lift + strength(s, x, y) end
  end
  return lift
end

-- The push at (x, y) from every running fan, pixels/frame² on each axis.
function airflow.push(x, y)
  local fx, fy = 0, 0
  for _, s in ipairs(sources) do
    local f = strength(s, x, y)
    if f > 0 then fx, fy = fx + f * s.dx, fy + f * s.dy end
  end
  return fx, fy
end

return airflow
