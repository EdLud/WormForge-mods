local root = MOLE_SHOPPER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../mole_shopper/")
package.path = root .. "?.lua;" .. package.path
local claim, turn_start, turn_end
local cursors = {}
wa = {
  weapons = {replace = function(spec) claim = spec end},
  cursor = {spawn = function(spec)
    local actor = {spec = spec, freed = false}
    function actor:despawn()
      assert(not self.freed, "cursor must not be freed twice")
      self.freed = true
    end
    cursors[#cursors + 1] = actor
    return actor
  end},
  on = {
    turn_start = function(fn) turn_start = fn end,
    turn_end = function(fn) turn_end = fn end,
    draw = function() end,
  },
}
local weapon = require("weapons/far_sight")
weapon.install{id = "px.far_sight", option = function() return true end}
local ammo = 2
local worm = {id = 1, turn = true, hp = 100, weapon = "px.far_sight"}
function worm:ammo() return ammo end
local function select()
  claim.on_select.on{worm = worm, x = 500, y = 300}
end
select()
assert(#cursors == 1 and cursors[1].spec.owner == worm)
assert(cursors[1].spec.x == 500 and cursors[1].spec.y == 300)
cursors[1].spec.on()
assert(not cursors[1].freed, "cursor stays for accepted or rejected placements")
select()
assert(cursors[1].freed and #cursors == 2, "reselection replaces rather than duplicates cursor")
worm.weapon = "stock.bazooka"
cursors[2].spec.on()
assert(cursors[2].freed, "switching away must remove cursor")
turn_end()
assert(#cursors == 2)
worm.weapon = "px.far_sight"
turn_start{worm = worm}
assert(#cursors == 3 and cursors[3].spec.x == nil, "new turn uses current native pointer")
turn_end()
assert(cursors[3].freed)
turn_start{worm = worm}
worm.hp = 0
cursors[4].spec.on()
assert(cursors[4].freed, "death must remove cursor without erasing placed lights")
worm.hp = 100
select()
ammo = 0
cursors[5].spec.on()
assert(cursors[5].freed, "last unit spent must remove cursor")
select()
assert(#cursors == 5, "empty weapon must not spawn cursor")
ammo = -1
select()
assert(#cursors == 6)
worm.turn = false
cursors[6].spec.on()
assert(cursors[6].freed)
select()
assert(#cursors == 6, "inactive worm must not spawn cursor")
print("Far Sight cursor selection, reselection, switching, turn, death and ammo lifecycle passed")
