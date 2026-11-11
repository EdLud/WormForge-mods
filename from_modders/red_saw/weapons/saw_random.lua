-- Random saws: seeds the map with teamless saws, one per vertical slice, on the first turn.

local saw = require("lib/saw")

local function size() return wa.random(17, 65) / 100 end
local function retry_size() return wa.random(162, 642) / 1000 end

local function random_depth()
  return wa.random(1, 2) == 1
    and wa.depth.OBJECTS + 1 or wa.depth.BEHIND_TERRAIN + 2
end

local function clear_at(x, y, size)
  local radius = math.max(1, size * 100)
  local search = math.max(1, radius * 0.32)
  local fit = math.min(64, math.max(1, math.ceil(radius + 3)))
  local offset = search > 10 and math.floor(search * 0.4) or 3
  local limit = radius * 1.8
  local rings = math.ceil(limit / search)
  for ring = 0, rings do
    local ring_r = ring * search
    if ring_r > limit then break end
    local step_deg = ring_r == 0 and 360
      or math.floor(math.max(15, 360 / (ring_r * 0.5)))
    local degree = 0
    while degree < 360 do
      local angle = degree * (math.pi / 180)
      local cx = math.floor(x + ring_r * wa.math.cos(angle) + 0.5)
      local cy = math.floor(y + ring_r * wa.math.sin(angle) + 0.5)
      local blocked = wa.world.trace{
        x0 = cx, y0 = cy, x1 = cx, y1 = cy + offset,
        radius = fit, with = { "worms", "mines", "oil" },
      }
      if not blocked then
        local h = wa.world.trace{
          x0 = cx - 8, y0 = cy - 8, x1 = cx + 8, y1 = cy + 8,
          radius = 0, with = { "terrain", "oil" },
        }
        if not h then return cx, cy end
      end
      degree = degree + step_deg
    end
  end
  return nil
end

local function attempt(a, st)
  if st.spawned >= st.quantity or st.slice >= st.quantity then
    a:despawn()
    return
  end

  local level = wa.world.size()
  local water = wa.world.water() or level.h
  local hi = math.max(101, math.floor(water - 100))
  local try_y = wa.random(100, hi)

  local sw = level.w / st.quantity
  local lo = math.max(30, math.min(level.w - 30, math.floor(st.slice * sw)))
  local hi_x = math.max(30, math.min(level.w - 30, math.floor((st.slice + 1) * sw)))
  if hi_x < lo then hi_x = lo end
  local x = wa.random(lo, hi_x)

  local down = wa.world.trace{
    x0 = x, y0 = try_y, x1 = x, y1 = math.floor(water - 70),
    radius = 0, with = { "terrain" },
  }
  local up = wa.world.trace{
    x0 = x, y0 = try_y, x1 = x, y1 = -70,
    radius = 0, with = { "terrain" },
  }
  local dh, uh = down and down.hit, up and up.hit
  local hit
  if dh and uh then
    hit = wa.random(1, 2) == 1 and down or up
  elseif dh then
    hit = down
  elseif uh then
    hit = up
  end

  if hit then
    local sx, sy = clear_at(hit.x, hit.y - 5, st.size)
    if sx then
      local depth = random_depth()
      local electric = wa.random(1, 100) <= st.electric_chance
      local s = saw.spawn{
        x = sx, y = sy - 1, size = st.size, team = nil,
        depth = depth, electric = electric,
      }
      if s then
        st.spawned = st.spawned + 1
        st.slice = st.slice + 1
        st.attempts = 0
        st.size = size()
        if st.spawned >= st.quantity then a:despawn() end
        return
      end
    end
  end
  st.attempts = st.attempts + 1
  if st.attempts < 10 then
    st.size = retry_size()
  else
    st.slice = st.slice + 1
    st.attempts = 0
    st.size = size()
  end
  if st.slice >= st.quantity then a:despawn() end
end

local function fetchWorm()
  for _, w in ipairs(wa.worms.all()) do
    if w and w.kind == "worm" then return w end
  end
end

return {
  install = function(ctx)
    saw.install(ctx)
    local quantity = math.max(1, math.min(12,
      math.floor(ctx.option("quantity") or 4)))
    local electric_chance = math.max(0, math.min(100,
      math.floor(ctx.option("electric_chance") or 14)))
    local started = false
    wa.on.turn_start(function()
      if started then return end
      started = true
      local st = { quantity = quantity, slice = 0, attempts = 0,
        spawned = 0, size = size(), electric_chance = electric_chance }
      local owner = fetchWorm()
      if not owner then return end
      wa.actors.spawn{
        owner = owner,
        sprite = false, x = 0, y = 0, gravity = false, collide = false,
        drown = false, persist = true,
        on = function(a) attempt(a, st) end,
      }
    end)
  end,
}
