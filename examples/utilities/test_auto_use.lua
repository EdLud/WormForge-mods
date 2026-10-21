-- Run from the repo root: lua mods/examples/utilities/test_auto_use.lua
local definition = dofile("mods/examples/utilities/weapons/plus_ten.lua")
local id = "utilities.plus_ten"

local function setup(policy, ammo)
  local hooks, clock, weapon = {}, 30000, nil
  local worm = { id = 17, ammo_group = 2, held = ammo, turn = true }
  function worm:ammo(weapon_id, change)
    assert(weapon_id == id)
    if change and self.held >= 0 then self.held = math.max(0, self.held + change) end
    return self.held
  end
  wa = {
    msg = { FRAME_FINISH = 2 },
    weapons = { replace = function(spec) weapon = spec end },
    world = {
      turn_clock = function() return clock end,
      set_turn_clock = function(value) clock = value end,
    },
    worms = { all = function() return { worm } end },
    on = setmetatable({}, { __index = function(_, name)
      return function(fn) hooks[name] = fn end
    end }),
  }
  definition.install({ id = id, data = { on_collect = policy } })
  local function event(name, ev) if hooks[name] then hooks[name](ev) end end
  return {
    worm = worm,
    start = function()
      event("turn_start", { worm = worm })
      -- The surrounding native turn setup completes before the first frame.
      event("worm_message", worm)
    end,
    next_turn = function()
      event("turn_cleanup", { worm = worm })
      event("turn_start", { worm = worm })
      clock = 30000 -- Native setup overwrites anything added inside StartTurn.
      event("worm_message", worm)
    end,
    collect = function(amount)
      if worm.held >= 0 then worm.held = worm.held + amount end
      event("weapon_grant", { worm_id = worm.id, items = { { weapon = id, amount = amount } } })
    end,
    fire = function()
      worm:ammo(id, -1) -- WA consumes the manually fired unit.
      weapon.on_fire({ worm = worm })
    end,
    clock = function() return clock end,
  }
end

local t = setup("use", 0)
t.start()
assert(t.clock() == 30000)
t.collect(2)
assert(t.worm.held == 1 and t.clock() == 40000, "two-unit pickup activates one and banks one")
t.collect(2)
assert(t.worm.held == 3 and t.clock() == 40000, "active pickup banks the full quantity")
t.next_turn()
assert(t.worm.held == 2 and t.clock() == 40000, "next turn consumes exactly one")
t.start()
assert(t.worm.held == 2 and t.clock() == 40000, "repeated start cannot consume again")

t = setup("use", -1)
for _ = 1, 3 do
  t.next_turn()
  assert(t.worm.held == -1 and t.clock() == 40000, "infinite auto-use remains infinite")
  t.collect(2)
  assert(t.worm.held == -1 and t.clock() == 40000)
end

t = setup("keep", 2)
t.start()
t.collect(2)
assert(t.worm.held == 4 and t.clock() == 30000, "Auto-Use=false only stocks")
t.fire()
assert(t.worm.held == 3 and t.clock() == 40000)
t.next_turn()
assert(t.worm.held == 3 and t.clock() == 30000)

t = setup("use", 2)
t.fire()
t.collect(2)
assert(t.worm.held == 3 and t.clock() == 40000, "manual use also marks the effect active")
print("PASS: Auto-Use, multi-unit pickups, banking, turn-start drain, infinite ammo and manual use")
