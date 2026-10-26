local root = MOLE_SHOPPER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../mole_shopper/")
package.path = root .. "?.lua;" .. package.path
package.preload["wf-lib/holds"] = function()
  return {PX_POSTURE = {}, PX_HANDS = {"hand.png"}}
end

-- Declarations must load with no native WA binding.
local lantern = require("weapons/lantern")
local sight = require("weapons/far_sight")
local moles = require("weapons/mole_bombs")
local claims, actors, draws, sounds, hooks, frame = {}, {}, {}, {}, {}, 0
local solid, solid_reads, denied = false, 0, 0
wa = {
  depth = {OBJECTS = 5},
  land = {solid = function(x, y)
    assert(x == 500.5 and y == 300.25)
    solid_reads = solid_reads + 1
    return solid
  end},
  hud = {message_top = function(text, options)
    assert(text:find("terrain") and options.to == "coalition" and options.alliance == 1)
    denied = denied + 1
  end},
  weapons = {replace = function(spec) claims[#claims + 1] = spec end,
    data = function(id)
      assert(id == "px.mole_bombs")
      return {clusters = {bit = {sprite = 152,
        dig = {dive_sprite = 158, sprite_1 = 159, sprite_2 = 160, sprite_3 = 160}}}}
    end},
  actors = {spawn = function(spec)
    local actor = {id = #actors + 1, x = spec.x, y = spec.y, spec = spec, gfx_values = {}}
    function actor:gfx(fields)
      for key, value in pairs(fields) do self.gfx_values[key] = value end
    end
    actors[#actors + 1] = actor
    return actor
  end},
  draw = {quad = function(spec) draws[#draws + 1] = spec end},
  sound = {play = function(target, path) sounds[#sounds + 1] = {target, path} end},
  world = {frame = function() return frame end, keys = function() return {shift = false} end},
  on = {turn_start = function() end, turn_end = function() end, draw = function(fn) hooks[#hooks + 1] = fn end,
    missile_frame = function(fn) hooks.missile = fn end},
}
dofile(root .. "../tests/tooltip_mock.lua")(root)

lantern.install()
local spec = claims[1]
assert(spec.copy_from == "stock.dynamite" and not spec.handling.ends_turn)
local owner = {id = 42, x = 100, y = 80, vx = 3, vy = 2, facing = -1, alliance = 1}
spec.on_fire{worm = owner}
local body = actors[1]
assert(body.spec.x == 100 and body.spec.y == 70)
assert(body.spec.vx == 1 and body.spec.vy == 1.5)
assert(body.spec.body.physics == "mine" and body.spec.body.hit_by == "all")
assert(body.spec.persist and body.spec.drown and body.spec.owner == owner)
assert(body.light.circle == 110 and body.light.cone.length == 0)
assert(body.light.seen_by == "owner" and not body.light.discover)
assert(body.gfx_values.tint == 0x0087E6)
frame = 100
hooks[1]()
assert(body.spec.vx == 1 and body.x == 100, "draw must never integrate physics")
assert(body.gfx_values.scale >= 0.46 and body.gfx_values.scale <= 0.50)
body.id = 99 -- Engine reused the actor's address for an unrelated actor.
body.gfx_values = {}
hooks[1]()
assert(next(body.gfx_values) == nil, "stale drawing records must not touch a recycled actor")

owner.hp = 100
local ammo, spent = 2, 0
function owner:ammo(id, change)
  assert(id == "px.far_sight")
  if change then
    assert(change == -1)
    spent = spent + 1
    if ammo ~= -1 then ammo = ammo + change end
  end
  return ammo
end
sight.install{id = "px.far_sight", option = function(key)
  assert(key == "terrain_blocking")
  return true
end}
spec = claims[2]
assert(spec.copy_from == "stock.teleport" and spec.eat_fire and not spec.handling.ends_turn)
assert(spec.on_select.cursor and spec.click_finish == false)
solid = true
spec.on_click{worm = owner, x = 500.5, y = 300.25}
assert(#actors == 1 and ammo == 2 and spent == 0 and denied == 1 and #sounds == 0,
  "rejected placement must not spawn, spend ammo or play the reveal sound")
solid = false
spec.on_click{worm = owner, x = 500.5, y = 300.25}
assert(ammo == 1 and spent == 1)
local marker = actors[2]
assert(marker.spec.sprite == false and not marker.spec.collide and not marker.spec.gravity)
assert(marker.spec.persist and not marker.spec.drown and marker.spec.solid == false)
assert(marker.spec.x == 500.5 and marker.spec.y == 300.25)
assert(marker.light.circle == 155 and marker.light.seen_by == "owner" and marker.light.shadow_cast)
assert(sounds[1][1] == marker and sounds[1][2] == "sounds/far_sight/reveal.wav")
frame = 1000 -- Far beyond PX's controller lifetime of 60 frames.
hooks[2]()
assert(#draws == 2 and marker.light.circle == 155, "Far Sight must remain after its controller would end")
owner.hp = 0
draws = {}
hooks[2]()
assert(#draws == 2, "the planter's death must not erase the remote light")
marker.id = 0
draws = {}
hooks[2]()
assert(#draws == 0, "freed markers stop drawing")

-- No ammunition or dead planter cannot create a marker.
ammo = 0
spec.on_click{worm = owner, x = 500.5, y = 300.25}
assert(#actors == 2 and spent == 1)
ammo = 1
spec.on_click{worm = owner, x = 500.5, y = 300.25} -- owner.hp is still zero
assert(#actors == 2 and spent == 1)
owner.hp = 100

-- With blocking disabled, skip the terrain bitmap query and reveal through it.
sight.install{id = "px.far_sight", option = function() return false end}
spec = claims[3]
solid = true
local reads = solid_reads
spec.on_click{worm = owner, x = 500.5, y = 300.25}
assert(#actors == 3 and ammo == 0 and spent == 2)
assert(solid_reads == reads and not actors[3].light.shadow_cast)
ammo = -1
spec.on_click{worm = owner, x = 500.5, y = 300.25}
assert(#actors == 4 and ammo == -1 and spent == 3)

moles.install{id = "px.mole_bombs"}
spec = claims[4]
assert(spec.hold.sheet == "sprites/mole_bombs/hold.png" and spec.hold.thrown)
assert(spec.copy_from == "stock.mole_bomb" and spec.fires.method == 3)
assert(spec.fires.type == 1 and spec.fires.launch_power_pct == 20)
assert(spec.handling.shots == 2 and spec.clusters.bit.explosion.power == 40)
wa.world.keys = function() return {shift = true} end
local function motion(sprite, vy, weapon, phase)
  local m = {id = 77, sprite = sprite, vy = vy, weapon = weapon or "px.mole_bombs", phase = phase or "pre"}
  hooks.missile(m)
  return m.vy
end
assert(motion(166, 0) == 0, "the parent mole never gets fast-drop")
for _, sprite in ipairs({152, 158, 159, 160}) do assert(motion(sprite, 1) == 9) end
assert(motion(152, 9) == 17 and motion(152, 10) == 10)
assert(motion(152, 0, "px.mole_bomb") == 0, "Highlander's placed mole remains unchanged")
assert(motion(152, 0, nil, "post") == 0, "accelerate only once per physics frame")
wa.world.keys = function() return {shift = false} end
assert(motion(152, 0) == 0)
print("Mole Shopper lights, lifetimes, throw velocity and isolated Shift fast-drop passed")
