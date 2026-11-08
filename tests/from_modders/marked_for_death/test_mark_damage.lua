-- Plain Lua harness for the mark's damage in lib/curse.lua. Run from anywhere:
--   lua tests/from_modders/marked_for_death/test_mark_damage.lua
-- No WA needed; the fake wa hands the hurt hook what the engine would.
local PACK_ROOT = (arg[0]:match("^(.*[/\\])") or "") .. "../../../from_modders/marked_for_death/"

local function setup()
  local hooks = {}
  local wa = {
    depth = { FRONT = 1, EFFECTS = 2 },
    on = setmetatable({}, { __index = function(_, name)
      return function(cb) hooks[name] = cb end
    end }),
    world = { frame = function() return 100 end, water = function() return 2000 end },
    worms = {},
    sound = { play = function() end },
    assets = { load = function() end },
    log = function() end,
  }
  local w = { id = 3, x = 0, y = 0, vx = 0, vy = 0, hp = 100, state = "standing", hurts = {} }
  -- The engine runs the hurt hook for a react = false hurt too, as a hit.
  function w:hurt(o)
    local h = { worm = self, kind = "bullet", phase = "pre", amount = o.amount, expected = o.amount }
    hooks.hurt(h)
    o.took = h.amount
    self.hurts[#self.hurts + 1] = o
  end
  wa.worms.all = function() return { w } end
  local env = setmetatable({ wa = wa, require = function() error("no SDK") end }, { __index = _G })
  local curse = assert(loadfile(PACK_ROOT .. "lib/curse.lua", "t", env))()
  curse.install()
  return curse, w, function(hit)
    hit.worm = w
    hooks.hurt(hit)
    return hit
  end
end

-- Unmarked: nothing changes.
do
  local _, _, hurt = setup()
  local hit = hurt{ kind = "bullet", phase = "pre", amount = 20, expected = 20 }
  assert(hit.amount == 20)
end

-- A hit, a flame and the axe's share are scaled in pre; part points count.
do
  local curse, w, hurt = setup()
  curse.mark(w, 1.5)
  assert(hurt{ kind = "bullet", phase = "pre", amount = 25, expected = 25 }.amount == 38)
  assert(hurt{ kind = "fire", phase = "pre", amount = 1, expected = 1 }.amount == 2)
  assert(hurt{ kind = "percent", phase = "pre", amount = 50 }.amount == 75)
  curse.mark(w, 2.5)
  assert(hurt{ kind = "percent", phase = "pre", amount = 50 }.amount == 100)
  -- Poison and nonlethal damage are not the mark's.
  assert(hurt{ kind = "poison", phase = "pre", amount = 5 }.amount == 5)
end

-- A blast: its damage for this worm, never its power.
do
  local curse, w, hurt = setup()
  curse.mark(w, 1.15)
  local hit = hurt{ kind = "blast", phase = "pre", amount = 50, power = 50, damage = 20, expected = 20 }
  assert(hit.damage == 23 and hit.amount == 50, tostring(hit.damage))
  -- WA takes nothing (Phased Worms, the hit lockout): left alone.
  hit = hurt{ kind = "bullet", phase = "pre", amount = 20, expected = 0 }
  assert(hit.amount == 20)
  -- On a newer DLL, post adds nothing.
  hurt{ kind = "blast", phase = "post", amount = 50, damage = 23, expected = 23, lost = 23 }
  assert(#w.hurts == 0)
end

-- 0.9.8 (no hit.expected): the blast's extra share in post, damage alone,
-- and that hurt is not scaled again.
do
  local curse, w, hurt = setup()
  curse.mark(w, 1.5)
  local hit = hurt{ kind = "blast", phase = "pre", amount = 50, power = 50, damage = 20 }
  assert(hit.damage == 20 and hit.amount == 50)
  hurt{ kind = "blast", phase = "post", amount = 50, damage = 20, lost = 20 }
  assert(#w.hurts == 1 and w.hurts[1].took == 10 and w.hurts[1].react == false)
end

print("marked for death damage: ok")
