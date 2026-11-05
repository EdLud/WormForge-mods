-- The Specialists Soldier zombie against a mock WA: turning (a cut lethal
-- hit, a blast, fall damage, drowning), walking, punching, leaping, a team out and
-- Lightning's restore.
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  print((ok and "  ok   " or "  FAIL ") .. name .. (detail and ("   [" .. tostring(detail) .. "]") or ""))
  if not ok then failed = failed + 1 end
end

local h, worms, frame, clock, log, cuts, landed, sounds
tab_allowed = true
local Worm = {}
Worm.__index = Worm
function Worm:heal(n, opts)
  if self.hp <= 0 and not (opts and opts.from_zero) then return self.hp end
  self.hp = math.max(self.hp, 0) + n
  self.healed = (self.healed or 0) + 1
  return self.hp
end
function Worm:hurt(spec)
  self.hp = self.hp - spec.amount
  self.hits = self.hits or {}
  self.hits[#self.hits + 1] = spec
end
function Worm:input(spec)
  self.inputs[#self.inputs + 1] = spec.key
  if spec.key == "tab" and self.turn and tab_allowed then self.turn = false end
end
function Worm:clear_keys() self.keys_cleared = true end
function Worm:release(vx, vy) self.released = { vx, vy } end
function Worm:use(id) self.used = self.used or {}; self.used[#self.used + 1] = id; return true end

local function worm(id, x, y)
  local w = setmetatable({ id = id, team = id // 16, x = x, y = y, hp = 150, state = "standing",
    facing = 1, gravity = 1, selectable = true, body_visible = true, name = "w", inputs = {} }, Worm)
  worms[#worms + 1] = w
  return w
end

local function reset()
  h, worms, frame, clock, log, cuts, landed, sounds = {}, {}, 0, 30000, {}, {}, false, {}
  package.loaded["scheme/specialists_zombie"] = nil
  package.loaded["lib/shared"] = nil
  wa = {
    log = function(s) log[#log + 1] = s end,
    msg = { FRAME_FINISH = 5 },
    depth = { WORMS = 1 },
    sorted = function(t)
      local keys = {}
      for k in pairs(t) do keys[#keys + 1] = k end
      table.sort(keys)
      return keys
    end,
    random = function(a) return a end,
    worms = { all = function() return worms end },
    world = {
      frame = function() return frame end,
      turn_clock = function() return clock end,
      set_turn_clock = function(ms) clock = ms end,
      gravity = function() return 0.25 end,
    },
    land = {
      trace = function() return landed end,
      cut = function(s) cuts[#cuts + 1] = s end,
    },
    draw = { quad = function() end },
    sound = { play = function(target, id) sounds[#sounds + 1] = { target, id } end },
    on = {
      hurt = function(f) h.hurt = f end,
      turn_start = function(f) h.start = f end,
      turn_end = function(f) h.stop = f end,
      worm_message = function(f) h.msg = f end,
      draw = function(f) h.draw = f end,
    },
  }
  local zombie = require("scheme/specialists_zombie")
  zombie.install(function(w) return w.id % 16 == 1 end, "Soldier")
  return zombie
end

-- One sim frame: every worm's FRAME_FINISH; the clock runs unless frozen.
local function step(frozen)
  frame = frame + 1
  if not frozen then clock = clock - 20 end
  for _, w in ipairs(worms) do h.msg(w, 5) end
end

-- A blast reaches every worm with its power as the amount; WA takes off
-- `damage` for the distance (the amount itself by default).
local function hurt(w, amount, kind, damage)
  local hit = { phase = "pre", worm = w, amount = amount, kind = kind or "blast" }
  h.hurt(hit)
  w.hp = w.hp - (hit.kind == "blast" and (damage or hit.amount) or hit.amount)
  return hit
end

-- A lethal hit: cut to 1 HP, then a zombie with 100.
local zombie = reset()
local soldier, gunner = worm(17, 0, 0), worm(18, 1000, 0)
local enemy = worm(33, 2000, 0)
local hit = hurt(soldier, 200, "hit")
check("a lethal hit on the Soldier is cut to 1 HP", hit.amount == 149 and soldier.hp == 1, soldier.hp)
step()
check("the Soldier comes back with 100 HP", soldier.hp == 100, soldier.hp)
check("as a zombie WA's turns pass over", zombie.is_zombie(soldier) and soldier.selectable == false and soldier.name == "Zombie")
check("tinted green, lit and glowing", type(soldier.tint) == "table" and soldier.tint.color == 0x60FF60
  and soldier.tint.light > 0 and soldier.tint.glow > 0)
hurt(soldier, 200)
step()
check("a zombie isn't cut short: it dies", soldier.hp <= 0 and zombie.is_zombie(soldier), soldier.hp)
check("and doesn't turn again", soldier.healed == 1, soldier.healed)

-- A blast far off: its power is more than the Soldier's health, its damage
-- isn't. Left alone (it turned in a 2026-11-05 match).
zombie = reset()
soldier = worm(17, 0, 0); worm(18, 500, 0)
soldier.hp = 42
hit = hurt(soldier, 50, "blast", 0)
step()
check("a blast's power isn't its damage: a Soldier out of reach keeps its health",
  hit.amount == 50 and soldier.hp == 42 and not zombie.is_zombie(soldier), soldier.hp)
hit = hurt(soldier, 50, "blast", 30)
step()
check("nor is a blast that leaves it alive cut", soldier.hp == 12 and not zombie.is_zombie(soldier), soldier.hp)

-- A lethal blast: 0 HP, raised from zero on its next frame.
hurt(soldier, 50, "blast", 40)
step()
check("a Soldier a blast kills is raised from zero", soldier.hp == 100 and zombie.is_zombie(soldier), soldier.hp)

-- Fall damage: no hurt message, 0 HP: raised from zero.
zombie = reset()
soldier = worm(17, 0, 0); worm(18, 500, 0)
soldier.hp = 0
step()
check("a Soldier at 0 HP from a fall is raised from zero", soldier.hp == 100 and zombie.is_zombie(soldier), soldier.hp)

-- Drowning: dead for good.
zombie = reset()
soldier = worm(17, 0, 0); worm(18, 500, 0)
soldier.hp, soldier.state = 0, "drowning"
step()
check("a drowning Soldier stays dead", soldier.hp == 0 and not zombie.is_zombie(soldier))

-- Another class never turns.
zombie = reset()
gunner = worm(18, 0, 0); worm(17, 500, 0)
hurt(gunner, 500)
step()
check("only the Soldier turns", gunner.hp < 0 and not zombie.is_zombie(gunner))

-- Walking toward the turn's worm, of any team, only while the clock runs.
zombie = reset()
soldier, gunner = worm(17, 0, 0), worm(18, 500, 0)
enemy = worm(33, 100, 0)
soldier.hp = 0
step()
h.start({ worm = enemy })
step(true); step(true)
check("no step while the turn clock stands (hot-seat delay)", #soldier.inputs == 0, #soldier.inputs)
step(); step()
check("walks toward the worm being played", soldier.inputs[#soldier.inputs] == "right", soldier.inputs[#soldier.inputs])
h.start({ worm = gunner })     -- Tab to a teammate
gunner.x = -100
step(); step()   -- the clock is read again after a switch
check("Tab changes its target, its own team's too", soldier.inputs[#soldier.inputs] == "left")

-- The punch: WA's own Fire Punch, used without firing (worm:use), facing
-- the target, once a second at most.
enemy.x, enemy.y = 10, 0
h.start({ worm = enemy })
step(); step()
check("in reach it punches with WA's Fire Punch", soldier.used and soldier.used[1] == "stock.fire_punch", soldier.used and soldier.used[1])
check("it faces the target", soldier.facing == 1)
for _ = 1, 30 do step() end
check("no second punch within the attack cooldown", #soldier.used == 1, #soldier.used)
for _ = 1, 40 do step() end
check("another after it", #soldier.used == 2, #soldier.used)
enemy.x = 2000   -- out of reach
soldier.used = {}

-- An invisible target is left alone.
soldier.inputs, soldier.released = {}, nil
enemy.invisibility, enemy.x = true, 120
for _ = 1, 70 do step() end
check("an invisible target is ignored", #soldier.inputs == 0 and not soldier.released and #soldier.used == 0)
enemy.invisibility = nil

-- Out of reach, standing and in sight: a leap.
enemy.x, enemy.y = 300, -50
soldier.released = nil
step()
local v = soldier.released
check("a target out of reach in sight: a leap toward it", v and v[1] > 0 and v[2] < 0, v and (v[1] .. "," .. v[2]))
landed, soldier.released = true, nil
step()
check("no leap with land in the way", soldier.released == nil)
landed = false
enemy.x = 600
step()
check("no leap past 400 pixels", soldier.released == nil)

-- A team with only zombies left is out.
zombie = reset()
soldier, gunner = worm(17, 0, 0), worm(18, 500, 0)
worm(33, 900, 0)
soldier.hp = 0
step()
check("a zombie with a living teammate stays", soldier.hp == 100)
gunner.hp = 0
step()
check("its team's last human gone, the zombie is put to 0", soldier.hp == 0, soldier.hp)

-- Turning on its own turn: Tab hands the turn on; without worm selection
-- the turn's clock runs out.
zombie = reset()
soldier = worm(17, 0, 0); worm(18, 500, 0)
soldier.turn = true
hurt(soldier, 500)
step(); step()   -- it turns, then hands over
check("a Soldier turning on its own turn hands it on by Tab", soldier.inputs[1] == "tab" and soldier.turn == false)
zombie = reset()
soldier = worm(17, 0, 0); worm(18, 500, 0)
soldier.turn, tab_allowed = true, false
hurt(soldier, 500)
step(); step()
check("no worm selection: its keys are dropped and the clock run out", soldier.keys_cleared and clock == 0, clock)
tab_allowed = true

-- A dead zombie's grave brought back (the Health Zone at 1 HP, Lightning):
-- a new body with the team's lobby name, selectable and untinted. A Soldier
-- again, one that has had its turn.
zombie = reset()
soldier = worm(17, 0, 0); worm(18, 500, 0)
enemy = worm(33, 10, 0)
soldier.hp = 0
step()
hurt(soldier, 500)
step()
local revived = setmetatable({ id = 17, team = 1, x = 0, y = 0, hp = 1, state = "standing",
  facing = 1, gravity = 1, selectable = true, body_visible = true, name = "w", inputs = {} }, Worm)
worms[1] = revived
step()
check("a zombie's grave brought back is no zombie", not zombie.is_zombie(revived)
  and log[#log] == "Specialists: worm 17 comes back from its grave a Soldier", log[#log])
h.start({ worm = enemy })
step(); step()
check("it leaves the worm being played alone", #revived.inputs == 0 and revived.used == nil)
hurt(revived, 50)
step()
check("and has had its turn: a lethal hit isn't cut, it stays dead", revived.hp < 0 and not zombie.is_zombie(revived), revived.hp)

-- Lightning: a Soldier again, no health added, may turn once more.
zombie = reset()
soldier = worm(17, 0, 0); worm(18, 500, 0)
soldier.hp = 0
step()
local shared = require("lib/shared")
check("Lightning takes the strike for a zombie", shared.lightning_restores_worm(soldier) == true)
check("a Soldier again", not zombie.is_zombie(soldier) and soldier.selectable and soldier.name == "Soldier" and soldier.hp == 100)
check("its tint gone", soldier.tint == nil)
check("Lightning heals a plain worm as usual", shared.lightning_restores_worm(soldier) == false)
hurt(soldier, 500)
step()
check("restored, it may turn again", zombie.is_zombie(soldier) and soldier.hp == 100)

if failed > 0 then
  print(failed .. " FAILED")
  os.exit(1)
end
print("all passed")
