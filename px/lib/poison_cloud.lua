-- A lingering poison cloud: puffs that drift, bounce off the land and poison
-- the worms they touch. The Toxic Grenade's cloud and the Poison Grenade's.

local cloud = {}
local clouds = {}
local SMOKE = "sprites/toxic_grenade/smoke.png"
local FINISH_TURN = 55
local pending_end
local abs = math.abs

cloud.sprites = { SMOKE }

local function finish_candidate(worms, confirmed)
  local ending = pending_end
  pending_end = nil
  if not ending then return end
  if not confirmed then
    for _, w in ipairs(worms) do if w.turn then return end end
  end
  for _, s in ipairs(ending) do s.turns = s.turns - 1 end
end
local looks = setmetatable({}, { __mode = "k" })

local function random_signed()
  return wa.random(-10000, 10000) / 10000
end

local function puff(x, y)
  return { x = x, y = y, age = 0, life = 240 + 40 * random_signed(),
    vx = 3 * random_signed(), vy = 3 * random_signed() }
end

local wx, wy, ww, wn = {}, {}, {}, nil
local function gather(worms)
  wn = 0
  for _, w in ipairs(worms) do
    if w.hp > 0 then wn = wn + 1; wx[wn], wy[wn], ww[wn] = w.x, w.y, w end
  end
end

local function move(p, poison, worms, random, solid)
  local x, y, vx, vy = p.x, p.y, p.vx, p.vy
  local age = p.age + 1
  p.age = age
  for _ = 1, 128 do
    if not solid(x + vx, y + vy) then break end
    if random(0, 1) == 0 then
      vx = vy * -0.94; vy = vx * 0.94
    else
      vx = vy * 0.94; vy = vx * -0.94
    end
    if abs(vx) < 0.1 and abs(vy) < 0.1 then break end
  end
  if age % 8 == 0 then
    if not wn then gather(worms) end
    for k = 1, wn do
      if abs(wx[k] - x) < 20 and abs(wy[k] - y) < 20 then ww[k]:poison(poison) end
    end
  end
  p.x, p.y = x + vx, y + vy
  p.vx = vx * 0.995 + 0.05 * (random(-10000, 10000) / 10000)
  p.vy = (vy - 0.02) * 0.995 + 0.05 * (random(-10000, 10000) / 10000)
end

-- A cloud at (x, y), its actor owned by `worm` (else the first worm).
-- `turns`: how many turn ends it keeps puffing, 6 puffs every 8 frames;
-- nil puffs nothing more. `puffs`: how many it starts with. `poison`: what
-- a touch poisons by. `color`: 0xRRGGBB of the puffs.
function cloud.release(spec)
  local owner
  for _, w in ipairs(wa.worms.all()) do
    owner = owner or w
    if spec.worm and w.id == spec.worm.id then owner = w; break end
  end
  if not owner then return end
  local s = { x = spec.x, y = spec.y, age = 0, turns = spec.turns or -1, puffs = {},
    poison = spec.poison or 2, color = spec.color or 0x80DC80 }
  for _ = 1, spec.puffs or 0 do s.puffs[#s.puffs + 1] = puff(s.x, s.y) end
  local function step(a)
    local worms = wa.worms.all()
    finish_candidate(worms, false)
    local puffs, random, solid = s.puffs, wa.random, wa.land.solid
    local n, kept = #puffs, 0
    wn = nil
    for i = 1, n do
      local p = puffs[i]
      move(p, s.poison, worms, random, solid)
      if p.age <= p.life then kept = kept + 1; puffs[kept] = p end
    end
    for i = kept + 1, n do puffs[i] = nil end
    if s.turns >= 0 then
      if s.age % 8 == 0 then
        for _ = 1, 6 do puffs[#puffs + 1] = puff(s.x, s.y) end
      end
      s.age = s.age + 1
    elseif #puffs == 0 then
      for i, c in ipairs(clouds) do if c == s then table.remove(clouds, i); break end end
      a:remove()
    end
  end
  s.actor = wa.actors.spawn{ sprite = false, owner = owner, x = s.x, y = s.y, persist = true, light = false, on = step }
  clouds[#clouds + 1] = s
end

function cloud.setup()
  wa.on.worm_message(function(_, msg)
    if msg == wa.msg.TURN_STARTED then
      finish_candidate({}, true)
    elseif not pending_end then
      pending_end = {}
      for _, s in ipairs(clouds) do pending_end[#pending_end + 1] = s end
    end
  end, { msgs = { FINISH_TURN, wa.msg.TURN_STARTED } })
  -- One brush and one list of boxes, refilled each frame: no tables made.
  local MAX = 4096 * 7
  local PUFF = wa.draw.brush{ sprite = SMOKE, depth = wa.depth.OBJECTS }
  local list = {}
  wa.on.draw(function()
    if not clouds[1] then return end
    local floor = math.floor
    local n = 0
    for _, s in ipairs(clouds) do
      if s.actor.id ~= 0 then
        local puffs, color = s.puffs, s.color
        for i = 1, #puffs do
          local p = puffs[i]
          local v = looks[p]
          if not v then
            v = { rotation = wa.draw.random() * 6, size = 0.75 + 0.1 * (wa.draw.random() * 2 - 1) }
            looks[p] = v
          end
          local age, size = p.age, v.size
          local t = age / p.life
          if t > 1 then t = 1 end
          local side = 32 * (size + (1.75 - size) * t)
          list[n + 1], list[n + 2], list[n + 3], list[n + 4] = p.x, p.y, side, side
          list[n + 5], list[n + 6], list[n + 7] = v.rotation + age * 0.05, 0, floor(255 - 220 * t) * 0x1000000 + color
          n = n + 7
          if n == MAX then PUFF:boxes(list, 4096); n = 0 end
        end
      end
    end
    if n > 0 then PUFF:boxes(list, n // 7) end
  end)
end

return cloud
