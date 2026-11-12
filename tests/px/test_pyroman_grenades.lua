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

-- Homing Digger: the rocket's burst throws one digger at three times its last
-- speed; it drills an 8-pixel hole a frame in land at 3.5, speeds up in the air
-- and turns half way to the click every other frame; its burst starts fire.
reset()
local missile_hook, fires, cuts, solid = nil, {}, {}, false
wa.on.missile_frame = function(f) missile_hook = f end
wa.fire = { spawn = function(spec) fires[#fires + 1] = spec end }
wa.land = { cut = function(spec) cuts[#cuts + 1] = spec end }
wa.world = { collides = function() return solid end }
local hd = require("weapons/homing_digger")
def = hd.definition()
assert(def.copy_from == "stock.grenade" and def.click == "homing" and def.missile.burst == "nothing")
assert(def.missile.explosion.power == 0 and def.missile.ends_on_contact.land)
assert(def.missile.countdown == 0 and def.missile.fuse == 5000, "no timer, a fixed fuse")
hd.setup()
shooter.target = { x = 130, y = 40 }
fire("px.homing_digger")
missile_hook({ id = 0x100, weapon = "px.homing_digger", phase = "post", x = 20, y = 40, vx = 4, vy = -1 })
missile_hook({ id = 0x100, weapon = "px.homing_digger", phase = "post", x = 24, y = 39, vx = 0.5, vy = 0.2 })
def.on_explode({ missile = 0x100, x = 30, y = 40, vx = 0, vy = 0 })
hook(shooter, FINISH)
assert(#launched == 1 and sounds[#sounds] == 44)
local d = launched[1]
assert(d.vx == 12 and d.vy == -3, "three times its last speed over a pixel a frame")
assert(d.missile.action == "dig" and d.missile.explode_on_space and d.missile.fuse == 5000)
assert(d.missile.explosion.power == 50 and not d.missile.ends_on_contact.land)
local id = next_id
local m = { id = id, weapon = "px.homing_digger", phase = "pre", x = 30, y = 40, vx = 12, vy = -3 }
solid = true
missile_hook(m)
assert(#cuts == 1 and cuts[1].radius == 8 and sounds[#sounds] == 85, "drills in land")
m.phase = "post"
missile_hook(m)
assert(math.abs(m.vx - (12 + (3.5 - 12) * 0.5)) < 1e-9 and math.abs(m.vy - (-3 + 3 * 0.5)) < 1e-9,
  "turns half way to the click at the digging speed")
local vx = m.vx
missile_hook(m)
assert(m.vx == vx, "every other frame")
def.on_explode({ missile = id, x = 50, y = 40 })
hook(shooter, FINISH)
assert(#launched == 1, "a digger's burst throws no more")
assert(#fires == 1 and fires[1].count == 40 and fires[1].damage == 5 and sounds[#sounds] == 59)
wa.weapons.launch = function(spec)
  launched[#launched + 1] = spec
  def.on_explode({ missile = 0x6000, x = spec.x, y = spec.y })
  return nil
end
def.on_explode({ missile = 0x200, x = 30, y = 40, vx = 1, vy = 1 })
hook(shooter, FINISH)
hook(shooter, FINISH)
assert(#launched == 2, "a digger bursting as it is built throws no more")
assert(#fires == 2, "and starts its fire")
print("Homing Digger passed")

-- Homing Cluster Bomb: five clustlets fanned up from 20 pixels above the
-- blast; after 40 frames, with sound 44 three frames before, they turn 0.15 of
-- the way to the click every other frame; theirs throw no more.
reset()
local hc_frame
wa.on.missile_frame = function(f) hc_frame = f end
wa.math = { sin = math.sin, cos = math.cos }
local hcb = require("weapons/homing_cluster_bomb")
def = hcb.definition()
assert(def.copy_from == "stock.grenade" and def.click == "homing" and def.missile.explosion.power == 30)
hcb.setup()
shooter.target = { x = 400, y = 100 }
fire("px.homing_cluster_bomb")
def.on_explode({ missile = 0x100, x = 200, y = 100 })
hook(shooter, FINISH)
assert(#launched == 5, "five clustlets")
for i, c in ipairs(launched) do
  assert(c.y == 80 and c.missile.action == "none" and c.missile.fuse == 6000 and c.missile.explosion.power == 20)
  assert(c.vy < -8, "fanned about straight up")
end
assert(launched[1].vx < launched[5].vx, "from left to right")
local cm = { id = next_id, weapon = "px.homing_cluster_bomb", phase = "post", x = 200, y = 60, vx = 0, vy = -5 }
for _ = 1, 37 do hc_frame(cm) end
assert(sounds[#sounds] ~= 44)
hc_frame(cm)
assert(sounds[#sounds] == 44, "the homing sound three frames before")
assert(cm.vx == 0 and cm.vy == -5, "no homing in the first 40 frames")
for _ = 1, 2 do hc_frame(cm) end
assert(cm.vx == 0, "still waiting at frame 40")
hc_frame(cm)
local ux = 200 / math.sqrt(200 * 200 + 40 * 40)
assert(math.abs(cm.vx - ux * 10 * 0.15) < 1e-9, "then a pull towards the click")
def.on_explode({ missile = next_id, x = 200, y = 60 })
hook(shooter, FINISH)
assert(#launched == 5, "a clustlet's blast throws no more")
print("Homing Cluster Bomb passed")

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
