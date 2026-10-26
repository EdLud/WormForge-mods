-- Plain Lua harness for lib/custom_explosion.lua. Run from the bundle root:
--   fengari test_custom_explosion.lua
-- No WA: the fake wa and the fake zap/fx record what the module does.
local path = arg[1] or "lib/custom_explosion.lua"

local function near(a, b)
  return math.abs(a - b) < 1e-9
end

local function setup()
  local worm = { id = 1, kind = "worm", x = 100, y = 200, hp = 100,
    taken = false, hurts = 0 }
  function worm:hurt(arg)
    if type(arg) == "table" then
      self.last = { amount = arg.amount, vx = arg.vx, vy = arg.vy, push = true }
    else
      self.last = { amount = arg, push = false }
    end
    self.hp = self.hp - self.last.amount
    self.hurts = self.hurts + 1
  end
  local worms = { worm }
  local mines = {}
  local crates = {}
  local oil = {}
  local tazes, bursts, craters, arcs = {}, {}, {}, {}
  local nearby_calls = {}
  local zap = { taze = function(w, opts) tazes[#tazes + 1] = { worm = w, opts = opts } end }
  local fx = {
    burst = function(o) bursts[#bursts + 1] = o; return {} end,
    crater = function(o) craters[#craters + 1] = o end,
    arc = function(o) arcs[#arcs + 1] = o; return {} end,
  }
  local function nearby(x, y, radius, graves)
    nearby_calls[#nearby_calls + 1] = {
      x = x, y = y, radius = radius, graves = graves,
    }
    local out = {}
    local groups = { worms, mines, crates, oil }
    for i = 1, #groups do
      for j = 1, #groups[i] do
        local obj = groups[i][j]
        local dx, dy = obj.x - x, obj.y - y
        if dx * dx + dy * dy <= radius * radius then
          out[#out + 1] = obj
        end
      end
    end
    return out
  end
  local wa = {
    worms = { all = function() return worms end },
    mines = { all = function() return mines end },
    crates = { all = function() return crates end },
    oil = { all = function() return oil end },
    world = { electrical_nearby = nearby },
  }
  local env = setmetatable({ wa = wa }, { __index = _G })
  local M = assert(loadfile(path, "t", env))()
  return {
    M = M, wa = wa, worm = worm, zap = zap, fx = fx,
    tazes = tazes, bursts = bursts, craters = craters, arcs = arcs,
    nearby_calls = nearby_calls,
    set_mines = function(m) mines = m end,
    set_crates = function(c) crates = c end,
    set_oil = function(o) oil = o end,
  }
end

local function object(kind, x, y)
  local obj = { kind = kind, x = x, y = y, hits = 0 }
  function obj:hit(damage, vx, vy)
    self.hits = self.hits + 1
    self.damage, self.vx, self.vy = damage, vx, vy
    return true
  end
  return obj
end

-- Centre hit: full damage, no push, a 20-frame hold, PX's hole and radius.
local a = setup()
local hits = a.M.electric{ x = 100, y = 200, damage = 56, push = 56,
  zap = a.zap, fx = a.fx }
assert(hits == 1 and a.worm.last.amount == 56 and not a.worm.last.push,
  "centre damage lands without push")
assert(#a.tazes == 1 and a.tazes[1].opts.frames == 20
  and a.tazes[1].opts.push_x == 0 and a.tazes[1].opts.push_y == 0,
  "the hold takes over, with no push at the centre")
assert(#a.craters == 1 and a.craters[1].radius == 56, "PX's hole: destroyRadius = damage")
assert(#a.bursts == 1 and a.bursts[1].radius == 29
  and a.bursts[1].x == 100 and a.bursts[1].y == 200,
  "PX's effect radius: (damage + 2) / 2")
assert(#a.arcs == 0, "no mine, no chain arc")

-- Off-centre: falloff damage, and the push the hold releases on its way out.
local b = setup()
b.worm.x = 158
b.M.electric{ x = 100, y = 200, damage = 56, push = 56, zap = b.zap, fx = b.fx }
assert(b.worm.last.amount == 28, "half the damage at half the radius")
assert(#b.tazes == 1 and near(b.tazes[1].opts.push_x, 3.136)
  and near(b.tazes[1].opts.push_y, 0),
  "the push comes back on release, not into the hold")

-- Objects in the blast take the same falloff damage, through object:hit, from
-- one electrical_nearby pass. Mines are left to the chain arcs for now.
local j = setup()
local crate = object("crate", 130, 200)
local drum = object("oil", 150, 200)
local mine = object("mine", 120, 200)
local far = object("crate", 300, 200)
j.set_crates({ crate, far })
j.set_oil({ drum })
j.set_mines({ mine })
local jh = j.M.electric{ x = 100, y = 200, damage = 56, push = 56,
  zap = j.zap, fx = j.fx }
assert(jh == 3, "worm, crate and oil drum all count as hits")
assert(crate.hits == 1 and crate.damage == 41 and near(crate.vx, 4.592)
  and near(crate.vy, 0), "the crate takes falloff damage and push")
assert(drum.hits == 1 and drum.damage == 31 and near(drum.vx, 3.472)
  and near(drum.vy, 0), "the oil drum takes falloff damage and push")
assert(far.hits == 0, "an object outside the radius is untouched")
assert(mine.hits == 0, "a mine is not object:hit in this change")
assert(#j.nearby_calls == 1 and j.nearby_calls[1].x == 100
  and j.nearby_calls[1].y == 200 and j.nearby_calls[1].radius == 116
  and j.nearby_calls[1].graves == false,
  "one electrical_nearby query, without graves")

-- No electrical_nearby (older host): the groups are walked instead.
local k = setup()
local kcrate = object("crate", 130, 200)
k.set_crates({ kcrate })
k.wa.world = nil
local kh = k.M.electric{ x = 100, y = 200, damage = 56, push = 56,
  zap = k.zap, fx = k.fx }
assert(kh == 2 and kcrate.hits == 1 and kcrate.damage == 41,
  "the fallback still hits objects")

-- No taze: the hit itself carries the push, as PX's non-taze branch does.
local c = setup()
c.M.electric{ x = 100, y = 200, damage = 56, push = 56, taze = false,
  zap = c.zap, fx = c.fx }
assert(c.worm.last.push and c.worm.last.amount == 56, "damage and push in one hit")
assert(#c.tazes == 0, "no hold")

-- Past the radius: nothing. The effect and hole still land.
local d = setup()
d.worm.x = 300
local dh = d.M.electric{ x = 100, y = 200, damage = 56, push = 56,
  zap = d.zap, fx = d.fx }
assert(dh == 0 and d.worm.hurts == 0 and #d.tazes == 0, "outside the damage radius")
assert(#d.craters == 1 and #d.bursts == 1, "the hole and effect still land")

-- The switches: no hole, no effect, no chain.
local e = setup()
e.set_mines({ { x = 150, y = 200 } })
e.M.electric{ x = 100, y = 200, damage = 56, push = 56, destroy = false,
  effect = false, chain = false, zap = e.zap, fx = e.fx }
assert(#e.craters == 0 and #e.bursts == 0 and #e.arcs == 0, "everything switched off")
assert(e.worm.last.amount == 56, "the damage still lands")

-- A caught mine grows a bolt to the centre; one out of range does not.
local f = setup()
f.set_mines({ { x = 150, y = 200 }, { x = 400, y = 200 } })
f.M.electric{ x = 100, y = 200, damage = 56, push = 56, zap = f.zap, fx = f.fx }
assert(#f.arcs == 1 and f.arcs[1].from[1] == 150 and f.arcs[1].to[1] == 100
  and f.arcs[1].bulge == 5 and f.arcs[1].speed == 0.079 and f.arcs[1].terrain == false,
  "one chain arc to the mine in range")

-- Explicit params override PX's defaults.
local g = setup()
g.worm.x = 130
g.M.electric{ x = 100, y = 200, damage = 10, push = 0, radius = 50, hole = 7,
  effect_radius = 3, zap = g.zap, fx = g.fx }
assert(g.worm.last.amount == 4, "the explicit radius sets the falloff")
assert(g.craters[1].radius == 7 and g.bursts[1].radius == 3, "explicit hole and effect radius")

-- A lethal hit still tazes: the interaction is not gated by HP.
local i = setup()
i.worm.hp = 10
local ih = i.M.electric{ x = 100, y = 200, damage = 56, push = 56, zap = i.zap, fx = i.fx }
assert(ih == 1 and i.worm.hp <= 0, "lethal damage lands")
assert(#i.tazes == 1, "and the hold still starts")

-- No centre: nothing happens.
local h = setup()
assert(h.M.electric{ damage = 56, push = 56, zap = h.zap, fx = h.fx } == 0, "no centre, no boom")

print("custom_explosion: falloff, push, taze, objects, hole, chain, effect and options passed")
