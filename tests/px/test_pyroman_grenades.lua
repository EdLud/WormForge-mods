-- PyroMan's grenades and the TeleNade: each one's burst against a mock WA.

local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function() return { PX_POSTURE = {}, PX_HANDS = { "hand.png" } } end

local FIRE, FINISH = 1, 2
local hook, launched, arrows, sounds, next_id
local shooter = { id = 7, turn = true, hp = 100 }

local function reset()
  hook, launched, arrows, sounds, next_id = nil, {}, {}, {}, 0x5000
  wa = {
    msg = { FIRE_WEAPON = FIRE, FRAME_FINISH = FINISH },
    on = { worm_message = function(f) hook = f end },
    random = function(lo, hi) return lo end,
    weapons = { launch = function(spec)
      launched[#launched + 1] = spec
      next_id = next_id + 1
      return next_id
    end },
    arrows = { spawn = function(spec) arrows[#arrows + 1] = spec; return #arrows end },
    sound = { play = function(_, id) sounds[#sounds + 1] = id end },
    worms = { all = function() return { shooter } end },
  }
end

local function fire(id)
  shooter.weapon = id
  hook(shooter, FIRE)
end

-- Fire Cluster Bomb: five clustlets bursting into fire; theirs throw no more.
reset()
local fcb = require("weapons/fire_cluster_bomb")
local def = fcb.definition()
assert(def.copy_from == "stock.grenade" and def.missile.explosion.power == 20)
fcb.setup()
fire("px.fire_cluster_bomb")
def.on_explode({ missile = 0x100, x = 100, y = 50 })
hook(shooter, FINISH)
assert(#launched == 5, "five clustlets")
for _, c in ipairs(launched) do
  assert(c.owner == shooter and c.x == 100 and c.y == 50)
  assert(c.missile.burst == "fire" and c.missile.fuse == 1000 and c.missile.sprite == 54)
  assert(c.vx == -3 and c.vy == -10)
end
def.on_explode({ missile = 0x5001, x = 100, y = 50 })
hook(shooter, FINISH)
assert(#launched == 5, "a clustlet's burst throws no more")
print("Fire Cluster Bomb passed")

-- Digging Cluster Bomb: five digging clustlets at PX's fixed speeds.
reset()
local dcb = require("weapons/digging_cluster_bomb")
def = dcb.definition()
assert(def.missile.action == "dig" and not def.missile.ends_on_contact.land)
dcb.setup()
fire("px.digging_cluster_bomb")
def.on_explode({ missile = 0x100, x = 10, y = 20 })
hook(shooter, FINISH)
assert(#launched == 5)
assert(launched[1].vx == 0 and launched[1].vy == -10 and launched[5].vx == -6 and launched[5].vy == 6)
for _, c in ipairs(launched) do
  assert(c.missile.fuse == 2500 and c.missile.burst == "fire" and c.missile.dig.sprite_1 == 54)
end
def.on_explode({ missile = 0x5003, x = 10, y = 20 })
hook(shooter, FINISH)
assert(#launched == 5)
print("Digging Cluster Bomb passed")

-- Homing Digger: one digger on at the bomb's speed; a digger's burst ends it,
-- also when it bursts while WA builds it.
reset()
local hd = require("weapons/homing_digger")
def = hd.definition()
assert(def.copy_from == "stock.cluster_bomb" and def.missile.action == "homing")
assert(def.missile.explosion.power == 0)
assert(def.missile.countdown == 0 and def.missile.fuse == 5000, "no timer, a fixed fuse")
hd.setup()
fire("px.homing_digger")
def.on_explode({ missile = 0x100, x = 30, y = 40, vx = 4.5, vy = -2 })
hook(shooter, FINISH)
assert(#launched == 1)
local d = launched[1]
assert(d.vx == 4.5 and d.vy == -2 and d.missile.action == "dig" and d.missile.explode_on_space)
assert(d.missile.explosion.power == 40 and d.missile.fuse == 3000 and not d.missile.ends_on_contact.land)
def.on_explode({ missile = 0x5001, x = 50, y = 40 })
hook(shooter, FINISH)
assert(#launched == 1, "a digger's burst throws no more")
wa.weapons.launch = function(spec)
  launched[#launched + 1] = spec
  def.on_explode({ missile = 0x6000, x = spec.x, y = spec.y })
  return nil
end
def.on_explode({ missile = 0x200, x = 30, y = 40, vx = 1, vy = 1 })
hook(shooter, FINISH)
hook(shooter, FINISH)
assert(#launched == 2, "a digger bursting as it is built throws no more")
print("Homing Digger passed")

-- Ninja Bomb: 21 arrows from 5 pixels above the burst; the two sideways ones weightless.
reset()
local nb = require("weapons/ninja_bomb")
def = nb.definition
assert(def.missile.explosion.power == 0)
nb.setup()
fire("px.ninja_bomb")
def.on_explode({ missile = 0x100, x = 200, y = 100 })
hook(shooter, FINISH)
assert(#arrows == 21, "21 arrows")
local weightless = 0
for _, a in ipairs(arrows) do
  assert(a.owner == shooter and a.damage == 15)
  if a.gravity_pct == 0 then weightless = weightless + 1; assert(a.vy == 0) end
end
assert(weightless == 2)
assert(arrows[1].x == 200 and arrows[1].y == 70 and arrows[1].vx == 2 and arrows[1].vy == -8)
hook(shooter, FINISH)
assert(#arrows == 21, "one burst, once")
print("Ninja Bomb passed")

-- TeleNade: the teleport sound, then the worm where it went off.
reset()
local warps = {}
shooter.fits = function(_, x, y) return x == 16 and y == 26 end
shooter.warp = function(_, pos) warps[#warps + 1] = pos; return true end
def = require("weapons/telenade").definition
assert(def.missile.explosion.power == 0 and def.missile.explosion.push_pct == 0)
def.on_explode({ x = 20, y = 30 })
assert(#sounds == 1 and sounds[1] == 67)
assert(#warps == 1 and warps[1].x == 16 and warps[1].y == 26)
print("TeleNade passed")
