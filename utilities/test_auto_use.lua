-- Run from the repo root: lua mods/utilities/test_auto_use.lua
local definition = dofile((UTILITIES_ROOT or "mods/utilities/") .. "weapons/plus_n.lua")
local id = "utilities.plus_ten"

local function setup(policy, ammo, options)
  options = options or {}
  if options.seconds == nil then options.seconds = 10 end
  if options.bonus_mode == nil then options.bonus_mode = "once_keep" end
  if options.retreat_collect == nil then options.retreat_collect = "keep" end
  local hooks, clock, retreat, weapon = {}, 30000, 0, nil
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
      retreat = function() return retreat end,
      set_retreat = function(value)
        if retreat <= 0 then return false end
        retreat = value
        return true
      end,
    },
    worms = { all = function() return { worm } end },
    on = setmetatable({}, { __index = function(_, name)
      return function(fn) hooks[name] = fn end
    end }),
  }
  definition.install({ id = id, data = { auto_use = policy == "use" }, option = function(key)
    assert(options[key] ~= nil, key)
    return options[key]
  end })
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
      retreat = 0
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
    retreat = function(value)
      if value ~= nil then retreat = value end
      return retreat
    end,
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

-- Configured amount, stacking for multi-unit awards and repeated collections.
for _, seconds in ipairs({ 1, 10, 500 }) do
  t = setup("use", 0, { seconds = seconds, bonus_mode = "stack" })
  t.start(); t.collect(3); t.collect(2)
  assert(t.clock() == 30000 + 5 * seconds * 1000 and t.worm.held == 0)
end
t = setup("use", 4, { bonus_mode = "stack" })
t.start()
assert(t.clock() == 70000 and t.worm.held == 0, "stacked turn start activates finite inventory")
t.start()
assert(t.clock() == 70000, "repeated start has no inventory left to activate")
t = setup("use", -1, { bonus_mode = "stack" })
t.start(); t.start()
assert(t.clock() == 40000, "Select Worm/repeated turn-start notifications cannot stack infinite stock")
t.collect(3)
assert(t.clock() == 70000 and t.worm.held == -1, "infinite stock uses one at turn start, then the collected quantity")

-- Manual non-stacking use refunds duplicates rather than wasting inventory.
t = setup("keep", 3)
t.fire(); t.fire()
assert(t.clock() == 40000 and t.worm.held == 2)
t.next_turn(); t.fire()
assert(t.clock() == 40000 and t.worm.held == 1, "manual bonus resets next turn")
t = setup("keep", 3, { bonus_mode = "stack" })
t.fire(); t.fire()
assert(t.clock() == 50000 and t.worm.held == 1)

for _, stacking in ipairs({ false, true }) do
  t = setup("use", 0, { seconds = 7, bonus_mode = stacking and "stack" or "once_keep", retreat_collect = "activate" })
  t.retreat(3000); t.collect(2)
  assert(t.clock() == 30000, "retreat collection never extends the turn clock")
  assert(t.retreat() == (stacking and 17000 or 10000) and t.worm.held == (stacking and 0 or 1))
  t.collect(1)
  assert(t.retreat() == (stacking and 24000 or 10000), "retreat stacking obeys the same per-turn limit")

  t = setup("use", 0, { seconds = 7, bonus_mode = stacking and "stack" or "once_keep", retreat_collect = "keep" })
  t.retreat(3000); t.collect(2)
  assert(t.clock() == 30000 and t.retreat() == 3000 and t.worm.held == 2)
  t.next_turn()
  assert(t.clock() == (stacking and 44000 or 37000) and t.worm.held == (stacking and 0 or 1))
end

t = setup("use", 2, { retreat_collect = "nothing" })
t.retreat(3000); t.collect(3)
assert(t.worm.held == 2 and t.retreat() == 3000 and t.clock() == 30000, "discard affects only the new pickup")
t = setup("use", -1, { retreat_collect = "nothing" })
t.retreat(3000); t.collect(3)
assert(t.worm.held == -1 and t.retreat() == 3000, "discard cannot destroy infinite inventory")
for _, mode in ipairs({ "activate", "keep", "nothing" }) do
  t = setup("keep", 1, { retreat_collect = mode })
  t.retreat(3000); t.collect(2)
  assert(t.worm.held == 3 and t.retreat() == 3000 and t.clock() == 30000,
    "Auto-Use off keeps every retreat pickup regardless of retreat mode")
end

-- A bonus already used before retreat also blocks another non-stacking one.
t = setup("use", 0, { retreat_collect = "activate" })
t.collect(1); t.retreat(3000); t.collect(1)
assert(t.clock() == 40000 and t.retreat() == 3000 and t.worm.held == 1)

t = setup("use", 0, { seconds = 500, bonus_mode = "stack", retreat_collect = "activate" })
t.collect(99)
assert(t.clock() == 3600000, "turn clock respects the engine cap")
t.retreat(3599000); t.collect(1)
assert(t.retreat() == 3600000, "retreat clock respects the engine cap")
-- Discard mode removes surplus from a multi-unit pickup and later pickups.
t = setup("use", 0, { bonus_mode = "once_discard" })
t.start(); t.collect(3)
assert(t.clock() == 40000 and t.worm.held == 0, "first pickup activates one and discards its surplus")
t.collect(2)
assert(t.clock() == 40000 and t.worm.held == 0, "later pickups are discarded after the bonus")
t.next_turn(); t.collect(2)
assert(t.clock() == 40000 and t.worm.held == 0, "discard limit resets next turn")

t = setup("use", 4, { bonus_mode = "once_discard" })
t.start(); t.start(); t.collect(3)
assert(t.clock() == 40000 and t.worm.held == 3, "turn start and discarding pickups preserve older inventory")
t.next_turn()
assert(t.clock() == 40000 and t.worm.held == 2, "older stock supplies later turns")
t = setup("use", 2, { bonus_mode = "once_discard" })
t.collect(3)
assert(t.clock() == 40000 and t.worm.held == 2, "first pickup before automatic startup preserves older stock")
t = setup("use", -1, { bonus_mode = "once_discard" })
t.start(); t.collect(3); t.next_turn(); t.collect(2)
assert(t.clock() == 40000 and t.worm.held == -1, "discard mode leaves infinite inventory intact")

for _, bonus_mode in ipairs({ "stack", "once_keep", "once_discard" }) do
  for _, retreat_mode in ipairs({ "activate", "keep", "nothing" }) do
    t = setup("keep", 2, { bonus_mode = bonus_mode, retreat_collect = retreat_mode })
    t.start(); t.collect(3)
    assert(t.clock() == 30000 and t.worm.held == 5, "Auto-Use off stocks all ordinary pickups")
    t.retreat(3000); t.collect(2)
    assert(t.retreat() == 3000 and t.worm.held == 7, "Auto-Use off stocks all retreat pickups")
    t.fire(); t.fire()
    local stacking = bonus_mode == "stack"
    assert(t.retreat() == (stacking and 23000 or 13000) and t.worm.held == (stacking and 5 or 6),
      "manual duplicate use refunds the unit in either once mode")
  end
end

t = setup("use", 2, { bonus_mode = "once_discard", retreat_collect = "activate" })
t.retreat(3000); t.collect(3); t.collect(2)
assert(t.clock() == 30000 and t.retreat() == 13000 and t.worm.held == 2,
  "retreat activation discards new surplus while preserving older stock")
t = setup("use", 0, { bonus_mode = "once_discard", retreat_collect = "activate" })
t.collect(1); t.retreat(3000); t.collect(3)
assert(t.clock() == 40000 and t.retreat() == 3000 and t.worm.held == 0,
  "normal-turn bonus blocks retreat activation and discards that pickup")
t = setup("use", 0, { bonus_mode = "once_discard", retreat_collect = "keep" })
t.collect(1); t.retreat(3000); t.collect(3)
assert(t.retreat() == 3000 and t.worm.held == 3, "retreat keep overrides surplus discarding")
t.next_turn()
assert(t.clock() == 40000 and t.worm.held == 2, "saved retreat stock is retained after the next bonus")
t = setup("use", 2, { bonus_mode = "once_discard", retreat_collect = "nothing" })
t.retreat(3000); t.collect(3)
assert(t.retreat() == 3000 and t.worm.held == 2, "retreat nothing discards only the new pickup")
print("PASS: +N seconds, all three bonus modes, finite/infinite inventory, manual use and retreat policies")
