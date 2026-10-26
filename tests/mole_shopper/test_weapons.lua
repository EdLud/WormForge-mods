local root = MOLE_SHOPPER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../mole_shopper/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function() return {PX_POSTURE = {}, PX_HANDS = {"hand.png"}} end
local shotgun, vase = require("weapons/power_shotgun"), require("weapons/thrown_ming_vase")
local spec, message, draw, worms, chosen, sound = nil, nil, nil, {}, {}, 0
wa = {
  weapons = {replace = function(value) spec = value end,
    hold_sheet = function(id, n) chosen[#chosen + 1] = {id, n} end},
  msg = {WEAPON_RELEASED = 99},
  on = {worm_message = function(fn, filter)
      assert(filter.msgs[1] == wa.msg.WEAPON_RELEASED)
      message = fn
    end, draw = function(fn) draw = fn end},
  sound = {play = function() sound = sound + 1 end},
  worms = {all = function() return worms end},
}
shotgun.install{id = "px.power_shotgun"}
assert(spec.copy_from == "stock.shotgun" and spec.fire_repeat == 5)
assert(spec.gun.damage == 50 and spec.gun.explosion.push_pct == 300)
assert(not spec.on_fire, "keep WA's native shotgun firing, with its interruption guards")
local owner = {turn = true, weapon = "px.power_shotgun", state = "ready"}
worms = {owner}
draw()
assert(#chosen == 0)
owner.state = "firing"
draw()
assert(#chosen == 1 and chosen[1][1] == "px.power_shotgun" and chosen[1][2] == 1)
draw()
assert(#chosen == 1, "drawing the same state does not repeatedly switch sheets")
owner.state = "ready"
draw()
assert(#chosen == 2 and chosen[2][2] == 0)
message(owner)
assert(sound == 1)
owner.weapon = "stock.shotgun"
message(owner)
assert(sound == 1, "the stock shotgun does not play the custom sound")
vase.install{}
assert(spec.copy_from == "stock.ming_vase" and spec.fires.launch_power_pct == "charged")
assert(spec.fires.type == 1 and spec.fires.method == 3)
assert(spec.missile.explosion.power == 65 and spec.missile.ends_on_contact.land)
assert(spec.clusters.bit.explosion.power == 55 and spec.hold.thrown)
assert(not spec.on_fire and not spec.on_explode, "native vase flight and fragments own the shot")
print("Power Shotgun native firing, presentation switching and Thrown Ming Vase passed")
