-- Plain Lua harness for lib/custom_explosion.lua. Run from anywhere:
--   lua tests/from_modders/px_electric/test_custom_explosion.lua
-- No WA: the fake wa and the fake zap/fx record what the module does.
local PACK_ROOT = (arg[0]:match("^(.*[/\\])") or "") .. "../../../from_modders/px_electric/"
local path = arg[1] or PACK_ROOT .. "lib/custom_explosion.lua"

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
  local blasts = {}
  local zap = { taze = function(w, opts) tazes[#tazes + 1] = { worm = w, opts = opts } end }
  local fx = {
    burst = function(o) bursts[#bursts + 1] = o; return {} end,
    crater = function(o) craters[#craters + 1] = o end,
    arc = function(o) arcs[#arcs + 1] = o; return {} end,
  }
  -- The engine's blast, as far as these tests need it: falloff damage to live
  -- worms in range, object:hit to everything else. It leaves a 0 HP worm out.
  local function blast(o)
    blasts[#blasts + 1] = o
    local n = 0
    local groups = { worms, mines, crates, oil }
    for i = 1, #groups do
      for j = 1, #groups[i] do
        local obj = groups[i][j]
        local dx, dy = obj.x - o.x, obj.y - o.y
        local dist = math.sqrt(dx * dx + dy * dy)
        local dmg = math.floor(o.damage * (o.radius - dist) / o.radius)
        if dist < o.radius and dmg > 0 then
          if obj.kind == "worm" then
            if obj.hp > 0 then obj:hurt(dmg); n = n + 1 end
          elseif obj.hit and obj:hit(dmg, 0, 0) then
            n = n + 1
          end
        end
      end
    end
    return n
  end
  local wa = {
    worms = { all = function() return worms end },
    mines = { all = function() return mines end },
    crates = { all = function() return crates end },
    oil = { all = function() return oil end },
    world = { blast = blast },
  }
  local env = setmetatable({ wa = wa }, { __index = _G })
  local M = assert(loadfile(path, "t", env))()
  return {
    M = M, wa = wa, worm = worm, zap = zap, fx = fx,
    tazes = tazes, bursts = bursts, craters = craters, arcs = arcs,
    blasts = blasts,
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

-- Centre hit: one engine blast with PX's numbers, a 20-frame hold with no
-- push, PX's hole and radius.
local a = setup()
local hits = a.M.electric{ x = 100, y = 200, damage = 56, push = 56,
  zap = a.zap, fx = a.fx }
assert(#a.blasts == 1 and a.blasts[1].x == 100 and a.blasts[1].y == 200
  and a.blasts[1].damage == 56 and a.blasts[1].radius == 116
  and a.blasts[1].push_pct == 56 and a.blasts[1].kind == "taze",
  "one wa.world.blast, a taze, with PX's radius")
assert(hits == 1 and a.worm.last.amount == 56, "the blast's damage lands")
assert(#a.tazes == 1 and a.tazes[1].opts.frames == 20
  and a.tazes[1].opts.push_x == 0 and a.tazes[1].opts.push_y == 0,
  "the hold takes over, with no push at the centre")
assert(#a.craters == 1 and a.craters[1].radius == 56, "PX's hole: destroyRadius = damage")
assert(#a.bursts == 1 and a.bursts[1].radius == 29
  and a.bursts[1].x == 100 and a.bursts[1].y == 200,
  "PX's effect radius: (damage + 2) / 2")
assert(#a.arcs == 0, "no mine, no chain arc")

-- Off-centre: the push the hold releases on its way out.
local b = setup()
b.worm.x = 158
b.M.electric{ x = 100, y = 200, damage = 56, push = 56, zap = b.zap, fx = b.fx }
assert(#b.tazes == 1 and near(b.tazes[1].opts.push_x, 3.136)
  and near(b.tazes[1].opts.push_y, 0),
  "the push comes back on release, not into the hold")

-- A bundle's own kind replaces "taze".
local k = setup()
k.M.electric{ x = 100, y = 200, damage = 56, push = 56, kind = "shock",
  zap = k.zap, fx = k.fx }
assert(k.blasts[1].kind == "shock", "o.kind names the blast's hit")

-- Objects are the blast's: crates, drums and mines take its hit, and its
-- count is what electric returns.
local j = setup()
local crate = object("crate", 130, 200)
local drum = object("oil", 150, 200)
local far = object("crate", 300, 200)
j.set_crates({ crate, far })
j.set_oil({ drum })
local jh = j.M.electric{ x = 100, y = 200, damage = 56, push = 56,
  zap = j.zap, fx = j.fx }
assert(jh == 3 and crate.hits == 1 and drum.hits == 1 and far.hits == 0,
  "worm, crate and oil drum all count as hits")
assert(#j.tazes == 1, "only worms are held")

-- No taze: the blast carries the push; a live worm is not hit twice.
local c = setup()
c.M.electric{ x = 100, y = 200, damage = 56, push = 56, taze = false,
  zap = c.zap, fx = c.fx }
assert(c.worm.hurts == 1 and #c.tazes == 0, "the blast's hit only, no hold")

-- No taze and a worm already at 0 HP: the blast leaves it out, so the falloff
-- hit pushes it, as PX's M_GUNEXP does.
local z = setup()
z.worm.x, z.worm.hp = 158, 0
local zh = z.M.electric{ x = 100, y = 200, damage = 56, push = 56, taze = false,
  zap = z.zap, fx = z.fx }
assert(zh == 1 and z.worm.hurts == 1 and z.worm.last.push
  and z.worm.last.amount == 28 and near(z.worm.last.vx, 3.136),
  "a 0 HP worm gets PX's falloff push")

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
assert(g.blasts[1].radius == 50 and g.blasts[1].damage == 10,
  "the explicit radius goes to the blast")
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

print("custom_explosion: blast, push, taze, objects, hole, chain, effect and options passed")
