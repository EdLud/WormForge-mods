-- Where a stamp stuck in the land (the Javelin's spear, the Girder Launcher's
-- girder) may go without holding a worm inside new land.
--
-- The stamp is a bar along its frame's axis: frame f points f * 11.25 degrees
-- clockwise from up (both sheets, measured), `half_length` px each way from
-- its centre and `half_width` px either side. The engine plots it around the
-- pixel its position rounds down to. WA's worm shape is 9x16, hotspot (4,9);
-- a pixel more on every side absorbs a pixel's error in the measurements.
local stuck_stamp = {}

-- The bar's pixels, as offsets from its centre pixel, per frame and size.
-- Half-pixel steps along and across leave no pixel out on a slant.
local bars = {}
local function pixels(frame, bar, dx, dy)
  local key = frame .. ":" .. bar.half_length .. ":" .. bar.half_width
  local list = bars[key]
  if list then return list end
  list = {}
  local seen = {}
  for t2 = -2 * bar.half_length, 2 * bar.half_length do
    for s2 = -2 * bar.half_width, 2 * bar.half_width do
      local t, s = t2 / 2, s2 / 2
      local ox, oy = math.floor(dx * t - dy * s + 0.5), math.floor(dy * t + dx * s + 0.5)
      local k = ox * 1024 + oy
      if not seen[k] then
        seen[k] = true
        list[#list + 1] = { ox, oy }
      end
    end
  end
  bars[key] = list
  return list
end

local function holds(w, px, py, list, solid)
  local x0, x1 = math.floor(w.x) - 5, math.floor(w.x) + 5
  local y0, y1 = math.floor(w.y) - 10, math.floor(w.y) + 7
  for _, o in ipairs(list) do
    local x, y = px + o[1], py + o[2]
    -- Land already there gains nothing: the stamp's buried part.
    if x >= x0 and x <= x1 and y >= y0 and y <= y1 and not solid(x, y) then return true end
  end
  return false
end

-- The stamp centred at the impact (x, y), else as little deeper into the land
-- along its flight (its front end in land) as clears every worm, its back end
-- at most 10px past the impact (an impact on the last free pixel above a
-- worm's ground lies in its bottom row). Returns the centre and the depth, or
-- nil and the worm it cannot clear.
function stuck_stamp.place(x, y, frame, bar)
  local rad = math.rad(frame * 11.25)
  local dx, dy = wa.math.sin(rad), -wa.math.cos(rad)
  local list = pixels(frame, bar, dx, dy)
  local near = {}
  for _, w in ipairs(wa.worms.all()) do
    if w.hp > 0 and math.abs(w.x - x) < 80 and math.abs(w.y - y) < 80 then near[#near + 1] = w end
  end
  table.sort(near, function(p, q) return p.id < q.id end)
  local seen = {}
  local function solid(px, py)
    local k = px * 65536 + py
    local v = seen[k]
    if v == nil then v = wa.land.solid(px, py); seen[k] = v end
    return v
  end
  local held
  for d = 0, bar.half_length + 10 do
    local cx, cy = x + dx * d, y + dy * d
    local px, py = math.floor(cx), math.floor(cy)
    if d == 0 or solid(px + math.floor(dx * bar.half_length + 0.5), py + math.floor(dy * bar.half_length + 0.5)) then
      held = nil
      for _, w in ipairs(near) do
        if holds(w, px, py, list, solid) then held = w; break end
      end
      if not held then return cx, cy, d end
    end
  end
  return nil, held
end

return stuck_stamp
