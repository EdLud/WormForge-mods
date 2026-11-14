-- Weather simulation: when lightning strikes, and where.
local L = require("wf-lib/lightning")

local sim = {}

local SECOND = 50 -- frames
local MILLION = 1000000

-- Millionths a second whose 60 tries give `percent` a minute, found by halving with * and - only.
function sim.per_second(percent)
  if percent <= 0 then return 0 end
  if percent >= 100 then return MILLION end
  local miss = 1 - percent / 100
  local lo, hi = 0, MILLION
  while hi - lo > 1 do
    local mid = (lo + hi) // 2
    local keep = 1 - mid / MILLION
    local p = 1
    for _ = 1, 60 do p = p * keep end
    if p > miss then lo = mid else hi = mid end
  end
  return hi
end

-- What a strike aims at: mines, oil drums and crates first, else worms and graves.
function sim.targets()
  local out = {}
  for _, group in ipairs({ wa.mines, wa.oil, wa.crates }) do
    for _, obj in ipairs(group.all()) do out[#out + 1] = obj end
  end
  if #out > 0 then return out end
  for _, worm in ipairs(wa.worms.all()) do
    if worm.hp > 0 then out[#out + 1] = worm end
  end
  if wa.graves then
    for _, grave in ipairs(wa.graves.all()) do out[#out + 1] = grave end
  end
  return out
end

function sim.strike(cfg)
  local side = wa.random(0, 1) == 0 and -1 or 1
  if cfg.strike then
    local list = sim.targets()
    if #list == 0 then return end
    local obj = list[wa.random(1, #list)]
    return L.strike({ x = obj.x, y = obj.y, side = side, owner = "none", effects = true })
  end
  local size = wa.world.size()
  return L.strike({ x = wa.random(0, math.max(0, size.w - 1)), y = 0, side = side, owner = "none", effects = false })
end

-- On the weather's clock: a try once a second while it rains.
function sim.install(W)
  local cfg = W.kinds.rain
  local chance = sim.per_second(cfg.chance)
  if chance == 0 then return end
  W.ticks[#W.ticks + 1] = function(frame)
    if frame % SECOND ~= 0 or W.target.rain == 0 then return end
    if wa.random(1, MILLION) <= chance then sim.strike(cfg) end
  end
end

return sim
