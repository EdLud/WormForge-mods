-- Plain Lua harness for lib/fire_seq.lua's cancel.
--   fengari test_fire_seq_cancel.lua
local spawned = {}
local wa = {
  actors = {
    spawn = function(spec)
      local a = { dead = false, on = spec.on, x = spec.x or 0, y = spec.y or 0,
        despawn = function(self) self.dead = true end }
      spawned[#spawned + 1] = a
      return a
    end,
  },
  random = function() return 0 end,
  log = function() end,
}
local env = setmetatable({ wa = wa }, { __index = _G })
local seq = assert(loadfile("lib/fire_seq.lua", "t", env))()

local function worm(id)
  return { id = id, x = 100, y = 200, hp = 100, turn = true,
    weapon = "px.famas", state_id = 0x67, shots_fired = 0, shots_to_fire = 1 }
end

local function burst(owner, count, delay, on_shot)
  spawned = {}
  local shots, done, fired = {}, 0, {}
  local timer = seq.fire_sequential_actor({
    owner = owner, count = count, delay = delay,
    cancel_weapon = "px.famas",
    sprite = "bullet", x = 100, y = 200, vx = 0, vy = 1,
    on_shot = function(i) shots[#shots + 1] = i; if on_shot then on_shot(i) end end,
    on_done = function(_, n) done = done + 1; fired[#fired + 1] = n end,
  })
  return timer, shots, function() return done end, fired
end

-- Cancelled from outside a shot: the counters end at once, the timer settles.
local a = worm(1)
local timer, shots, done, fired = burst(a, 5, 2)
timer.on(timer)
assert(#shots == 1, "one shot before the cancel")
assert(seq.cancel(a) == true, "the burst is running")
assert(a.shots_fired == a.shots_to_fire, "the counters end now")
timer.on(timer)
assert(#shots == 1, "no shot after the cancel")
assert(done() == 1, "on_done once")
assert(fired[1] == 1, "on_done reports the shot already in flight")
assert(timer.dead, "the timer ends")
assert(seq.cancel(a) == false, "nothing left to cancel")

-- Cancelled from inside a shot: the shot still leaves, then the burst settles.
local b = worm(2)
local t2, s2, d2, f2 = burst(b, 5, 1, function(i) if i == 2 then seq.cancel(b) end end)
t2.on(t2)
assert(#s2 == 2, "shot 2 leaves before the burst stops")
assert(d2() == 1, "on_done once")
assert(f2[1] == 2, "the same-tick cancel counts shot 2")
assert(t2.dead, "the timer ends on the same tick")
assert(b.shots_fired == b.shots_to_fire, "the counters end now")

-- A death is an interruption, not a cancel: the timer settles the shots that
-- already left so ammo can be reconciled from on_done.
local d = worm(4)
local t5, s5, d5, f5 = burst(d, 5, 3)
t5.on(t5)
assert(#s5 == 1, "only the first shot has left")
d.hp = 0
t5.on(t5)
assert(#s5 == 1, "no shot fires into the death")
assert(d5() == 1 and f5[1] == 1, "an interrupted burst reports one shot")
assert(t5.dead, "the timer ends the interruption")
assert(d.shots_fired == d.shots_to_fire, "the counters end")

-- A cancelled burst lets the next one start.
local t3 = burst(a, 2, 1)
assert(t3, "a new burst starts once the old one lets go")

-- During the drain the burst is already settled: nothing left to pay.
local c = worm(3)
local t4, _, d4, f4 = burst(c, 2, 1)
while d4() == 0 do t4.on(t4) end
assert(f4[1] == 2, "a natural end reports every shot")
assert(not t4.dead, "the guard is still draining")
assert(seq.cancel(c) == false, "the drain has nothing left to settle")
assert(d4() == 1, "on_done is not repeated")

assert(seq.cancel(nil) == false, "no worm, no burst")
assert(seq.cancel({ id = 999 }) == false, "no burst for that worm")

print("fire_seq: cancel ends the counters, reports fired shots and lets a new burst start")
