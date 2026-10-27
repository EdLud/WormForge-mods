-- Plain Lua harness for weapons/famas.lua. Run from anywhere:
--   lua tests/from_modders/px_fire_seq/test_famas.lua
local PACK_ROOT = (arg[0]:match("^(.*[/\\])") or "") .. "../../../from_modders/px_fire_seq/"
local sounds, adds, samples, drops = {}, 0, 0, 0
local weapon, held, firing_art, fired
local land_hit

local trail = {
  BEAM = "beam", GLOW = "glow",
  install = function() end,
  add = function() adds = adds + 1 end,
  sample = function() samples = samples + 1 end,
  drop = function() drops = drops + 1 end,
}
local seq = {
  fire_sequential_actor = function(opts) fired = opts; return {} end,
}
local sb = {
  PX_POSTURE = { weaponlnk = "posture" },
  track_angle = function() return 0 end,
}
local hold_art = { add = function(art) firing_art = art end }

local wa = {}
wa.weapons = { replace = function(spec) weapon = spec end }
wa.sound = { play = function(_, path) sounds[#sounds + 1] = path end }
wa.math = { sin = math.sin, cos = math.cos, atan = math.atan }
wa.worms = { all = function() return wa.worm_list end }
wa.land = { trace = function() return land_hit or { hit = false } end }
wa.log = function() end
local owner = {
  id = 7, x = 100, y = 200, aim = 0.5, facing = 1, hp = 100, turn = true,
  weapon = "px.famas", state_id = 0x67,
}
local target = { id = 8, x = 20, y = 10, hp = 100 }
wa.worm_list = { owner, target }

local fakes = {
  ["lib/fire_seq"] = seq,
  ["lib/px_sprite_builder"] = sb,
  ["wf-lib/effects/trail"] = trail,
  ["lib/px_hold_art"] = hold_art,
}
local env = setmetatable({ wa = wa, require = function(name) return fakes[name] end },
  { __index = _G })
local mod = assert(loadfile(PACK_ROOT .. "weapons/famas.lua", "t", env))()
mod.install({ id = "px.famas", position = { row = "F3", column = 6 } })

assert(weapon and weapon.on_fire, "installed a weapon with on_fire")
assert(weapon.worm_sprites == sb.PX_POSTURE)
assert(weapon.hold.sheet == "sprites/famas/hold")
assert(firing_art.sheet == "sprites/famas/firing")
assert(weapon.hold.keep_while_firing == false)
assert(weapon.handling.ends_turn == false)
assert(weapon.fires.subtype == 4)

-- One trigger pull is one burst; the fourth is two rounds and dry-fires.
local function click()
  weapon.on_fire({ worm = owner, x = 100, y = 200 })
  return fired
end

local b1 = click()
assert(b1.count == 3 and b1.delay == 4, "first burst is three rounds")
b1.on_shot(1, owner)
b1.on_done(owner)

local b2 = click()
assert(b2.count == 3)
b2.on_shot(1, owner)
b2.on_done(owner)

local b3 = click()
assert(b3.count == 3)
b3.on_shot(1, owner)
b3.on_done(owner)

local b4 = click()
assert(b4.count == 2, "the last burst is two rounds")
b4.on_shot(1, owner)
b4.on_shot(2, owner)
b4.on_done(owner)

assert(#sounds == 5)
assert(sounds[1] == "sounds/famas/famas-burst.wav")
assert(sounds[2] == "sounds/famas/famas-burst.wav")
assert(sounds[3] == "sounds/famas/famas-burst.wav")
assert(sounds[4] == "sounds/famas/famas-2.wav")
assert(sounds[5] == "sounds/famas/dryfire1.wav")

local b5 = click()
assert(b5.count == 3, "the magazine starts again after the dry fire")
assert(b5.cancel_weapon == "px.famas" and b5.standoff == 8)
assert(b5.x(1, owner) == 100 and b5.y(1, owner) == 197)
assert(b5.vx(1, owner) == 23 and math.abs(b5.vy(1, owner)) < 1e-9)

owner.aim = 0
assert(math.abs(fired.vx(1, owner)) < 1e-9 and fired.vy(1, owner) == 23)
assert(fired.x(1, owner) == 102 and math.abs(fired.y(1, owner) - 193.85) < 1e-9)
owner.aim = 0.5

local exploded, dead, gfx
local actor = {
  id = 1, x = 10, y = 10, vx = 23, vy = 0, owner = owner,
  explode = function(_, opts) exploded = opts end,
  despawn = function() dead = true end,
  in_water = function() return false end,
  gfx = function(_, opts) gfx = opts end,
}
fired.on(actor)
assert(exploded and exploded.damage == 13 and exploded.id == 250)
assert(dead == true and drops == 1)
assert(adds == 1 and samples >= 1)
assert(gfx and gfx.depth == 22)

exploded, dead = nil, false
local land_actor = {
  id = 2, x = 10, y = 10, vx = 23, vy = 0, owner = owner,
  explode = function(_, opts) exploded = opts end,
  despawn = function() dead = true end,
  in_water = function() return false end,
  gfx = function() end,
}
land_hit = { hit = true, x = 15, y = 10 }
wa.worm_list = { owner }
fired.on(land_actor)
assert(exploded and exploded.damage == 13 and land_actor.x == 15 and dead)

print("famas: 3/3/3/2, gaps, sounds, PX hold/firing cells, bullet brain passed")
