-- Run from this bundle: lua test_weapon.lua
local claim
local spawned = {}
local hooks = {turn_start = {}, turn_end = {}}
wa = {
  weapons = {replace = function(spec) claim = spec end},
  cursor = {spawn = function(spec)
    local a = {spec = spec, dead = false}
    function a:despawn() self.dead = true end
    spawned[#spawned + 1] = a
    return a
  end},
  world = {pointer = function() return {x = 400, y = 200} end},
  fog = {
    set = function() error('weapon must not change the fog scheme') end,
    enable = function() error('weapon must not enable fog') end,
  },
  on = {},
}
for name, handlers in pairs(hooks) do
  wa.on[name] = function(fn) handlers[#handlers + 1] = fn end
end
local function emit(name, ev)
  for _, fn in ipairs(hooks[name]) do fn(ev) end
end
local component = dofile('weapon.lua')
assert(component.defaults.ammo.round_start == -1)
component.install{id = 'lights.cursor_light'}
assert(claim.copy_from == 'stock.teleport' and claim.fires.aims == true)
assert(claim.on_select.cursor and claim.eat_fire and claim.click_finish == false)
assert(claim.handling.ends_turn == false)
local worm = {id = 1, turn = true, hp = 100, weapon = 'lights.cursor_light'}
local select = function() claim.on_select.on{worm = worm, x = 120, y = 80} end
select()
local a = spawned[#spawned]
assert(a.spec.owner == worm and a.spec.x == 120 and a.spec.y == 80)
assert(a.light.mode == 'light' and a.light.shadow_cast == true and a.light.circle == 300)
assert(a.light.cone.length == 0 and a.light.discover == false and a.light.seen_by == 'owner')
claim.on_click{}
a.spec.on()
assert(not a.dead and #spawned == 1, 'clicking keeps one live cursor')
select()
assert(a.dead and a.light == false, 'reselecting removes the old source')
a = spawned[#spawned]
worm.weapon = 'stock.skip_go'
a.spec.on()
assert(a.dead and a.light == false, 'switching weapons removes the light')
worm.weapon = 'lights.cursor_light'
emit('turn_start', {worm = worm})
a = spawned[#spawned]
assert(a.spec.x == 400 and a.spec.y == 200, 'a remembered selection restores its cursor')
emit('turn_end', {worm = worm})
assert(a.dead and a.light == false)
emit('turn_start', {worm = worm})
a = spawned[#spawned]
worm.hp = 0
a.spec.on()
assert(a.dead and a.light == false, 'death removes the light')
local count = #spawned
worm.hp, worm.turn = 100, false
select()
assert(#spawned == count, 'inactive selection creates no cursor')
worm.turn, worm.weapon = true, 'stock.skip_go'
emit('turn_start', {worm = worm})
assert(#spawned == count, 'another weapon does not create a cursor')
print('PASS: shadow-casting light, click/reselect, weapon switch, turn transition, death and inactive selection')
