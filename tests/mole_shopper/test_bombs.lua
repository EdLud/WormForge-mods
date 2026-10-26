local root = MOLE_SHOPPER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../mole_shopper/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function() return {PX_POSTURE = {}, PX_HANDS = {"hand.png"}} end
local j, i = require("weapons/j_bomb"), require("weapons/i_bomb")
local specs = {}
wa = {weapons = {replace = function(spec) specs[#specs + 1] = spec end}}
j.install()
i.install()
local a, b = specs[1], specs[2]
assert(a.name == "j-bomb" and a.copy_from == "stock.dynamite")
assert(a.missile.fuse == 7000 and a.missile.explosion.power == 80)
assert(a.clusters.count == 28 and a.clusters.bit.explosion.power == 30)
assert(a.clusters.bit.fuse == 2000 and a.clusters.bit.gravity_pct == 100)
assert(a.clusters.bit.ends_on_contact.land and a.clusters.bit.ends_on_contact.worms)
assert(b.name == "i-bomb" and b.copy_from == "stock.grenade")
assert(b.missile.fuse == 3000 and b.missile.explosion.power == 80)
assert(b.clusters.count == 33 and b.clusters.launch_power_pct == 8)
assert(b.clusters.bit.action == "bounce" and b.clusters.bit.explosion.power == 30)
assert(not a.on_fire and not b.on_fire and not a.on_explode and not b.on_explode,
  "native records own both stages; there are no theme scripts or extra simulation drivers")
for _, spec in ipairs(specs) do
  assert(not spec.sounds, "no theme audio ships with the neutral bombs")
  assert(spec.sprite:find("sprites/") and spec.cluster.sprite:find("sprites/"))
  assert(spec.hold.thrown and spec.hold.sheet:find("hold.png"))
end
print("Neutral bombs preserve native parent/child gameplay and use scoped neutral artwork")
