-- Homing targets for missiles and other x/y/vx/vy objects.

local M = {}

local entries = {}
local order = {}
local on_target = {}
local installed = false
local STALE = 3

local worm_frame, candidates, by_id

local function object_id(object)
  if type(object) == "number" then return object end
  return object and object.id
end

local function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
  end
end

local function worms()
  local frame = wa.world.frame() or 0
  if frame == worm_frame then return candidates, by_id end
  worm_frame = frame
  candidates, by_id = {}, {}
  local list = wa.worms.all()
  for i = 1, #list do
    local w = list[i]
    if w.hp > 0 then
      candidates[#candidates + 1] = w
      by_id[w.id] = w
    end
  end
  return candidates, by_id
end

local function release(entry)
  local id = entry.targetId
  if not id then return end
  local counts = entry.on_target
  local n = (counts[id] or 1) - 1
  if n > 0 then counts[id] = n else counts[id] = nil end
  entry.targetId = nil
end

local function remove_at(i)
  local entry = entries[order[i]]
  if entry then
    release(entry)
    entries[entry.id] = nil
  end
  table.remove(order, i)
end

local function visible(m, w)
  local hit = wa.land.trace(m.x, m.y, w.x, w.y)
  return not (hit and hit.hit)
end

local function acquire(entry, m, list, owner)
  release(entry)
  local best, best_d2
  local counts = entry.on_target
  for i = 1, #list do
    local w = list[i]
    if w.id ~= (owner and owner.id)
      and (not owner or w.team ~= owner.team)
      and (not entry.max_target or (counts[w.id] or 0) < entry.max_target) then
      local dx, dy = w.x - m.x, w.y - m.y
      local d2 = dx * dx + dy * dy
      if d2 <= entry.sensor2 and (not best_d2 or d2 < best_d2)
        and visible(m, w) then
        best, best_d2 = w, d2
      end
    end
  end
  if best then
    entry.targetId = best.id
    counts[best.id] = (counts[best.id] or 0) + 1
  end
  return best
end

local function steer(entry, m, tx, ty)
  local dx, dy = tx - m.x, ty - m.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d > 0 then dx, dy = dx / d, dy / d end
  m.vx = m.vx + (dx * entry.speed - m.vx) * entry.strength
  m.vy = m.vy + (dy * entry.speed - m.vy) * entry.strength
end

local function update(entry, m, list, by_id)
  if entry.duration and entry.age >= entry.duration then return false end
  entry.age = entry.age + 1

  if not entry.armed then
    local owner = entry.owner
    if owner then
      local dx, dy = m.x - owner.x, m.y - owner.y
      if dx * dx + dy * dy > entry.arm_dist * entry.arm_dist then
        entry.armed = true
        entry.cd = 0
      end
    else
      entry.armed = true
    end
    return true
  end

  entry.cd = entry.cd - 1
  if entry.cd > 0 then return true end
  entry.cd = entry.cooldown

  local target = entry.targetId and by_id[entry.targetId]
  if target then
    local dx, dy = target.x - m.x, target.y - m.y
    if target.hp <= 0 or dx * dx + dy * dy > entry.sensor2
      or not visible(m, target) then
      release(entry)
      target = nil
    end
  end

  if not target then target = acquire(entry, m, list, entry.owner) end
  if target then
    steer(entry, m, target.x, target.y)
  else
    entry.cd = entry.no_target_cd
  end
  return true
end

local function purge(frame)
  for i = #order, 1, -1 do
    local entry = entries[order[i]]
    if entry and frame - entry.seen > STALE then remove_at(i) end
  end
end

function M.tick(m)
  if type(m) ~= "table" then return end
  local entry = entries[m.id]
  if not entry then return end
  local frame = wa.world.frame() or 0
  entry.seen = frame
  local list, by_id = worms()
  if not update(entry, m, list, by_id) then M.remove(m.id) end
  purge(frame)
end

function M.install()
  if installed then return end
  installed = true
  wa.on.missile_frame(function(m)
    if m.phase == "post" then M.tick(m) end
  end)
end

function M.add(object, speed, strength, duration, owner)
  local id = object_id(object)
  if not id then return nil end
  local entry = entries[id]
  if entry then return entry end

  entry = {
    id = id,
    object = object,
    speed = speed or 0,
    strength = strength or 0,
    duration = duration,
    age = 0,
    owner = owner or current_worm(),
    sensor2 = math.huge,
    cooldown = 0,
    no_target_cd = 0,
    arm_dist = 0,
    max_target = nil,
    on_target = on_target,
    targetId = nil,
    cd = 0,
    armed = true,
    seen = wa.world.frame() or 0,
  }
  entries[id] = entry
  order[#order + 1] = id
  return entry
end

function M.group()
  return {}
end

function M.get(object)
  return entries[object_id(object)]
end

function M.remove(object)
  local id = object_id(object)
  if not id then return end
  local entry = entries[id]
  if not entry then return end
  release(entry)
  entries[id] = nil
  for i = 1, #order do
    if order[i] == id then
      table.remove(order, i)
      break
    end
  end
end

function M.clear()
  for i = 1, #order do
    local entry = entries[order[i]]
    if entry then release(entry) end
  end
  entries, order, on_target = {}, {}, {}
  worm_frame, candidates, by_id = nil, nil, nil
end

return M
