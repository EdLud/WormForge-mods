-- Plain Lua harness for weapons/electric_mine.lua. Run from mods/px:
--   fengari test_electric_mine.lua
local installed, mine_call, blast_call = nil, nil, nil
local fx = {
  SPARK = "wf-lib/effects/sprites/px_effects/spark",
  BLOB = "wf-lib/effects/sprites/px_effects/glow.png",
  SMOKE = "wf-lib/effects/sprites/px_effects/cloud.png",
  install = function(o) installed = o end,
  mine = function(o) mine_call = o; return {} end,
}
local zap = {}
local trail = {
  BEAM = "wf-lib/effects/sprites/px_effects/beam.png",
  GLOW = "wf-lib/effects/sprites/px_effects/beam_glow.png",
}
local explosion = {
  electric = function(o) blast_call = o; return 1 end,
}
local wa
wa = {
  weapons = { replace = function(spec) wa.spec = spec end },
  depth = { FRONT = 0x10000 },
}
local fakes = {
  ["wf-lib/effects/px_effects"] = fx,
  ["lib/electric_damage"] = zap,
  ["lib/custom_explosion"] = explosion,
  ["wf-lib/effects/trail"] = trail,
}
local env = setmetatable({ wa = wa, require = function(name) return fakes[name] end },
  { __index = _G })
local mod = assert(loadfile("weapons/electric_mine.lua", "t", env))()
mod.install()

local spec = assert(wa.spec, "installed a weapon")
assert(installed and installed.trail == true, "installed the effects with the trail")
assert(spec.copy_from == "stock.mine" and spec.name == "Electric Mine")
assert(spec.panel_icon == "sprites/elemine.png")
assert(spec.mine.explosion.power == 0, "WA's own blast is silenced")
assert(type(spec.on_place.on) == "function" and type(spec.on_explode.on) == "function")
for _, path in ipairs({ "sprites/lightning/glow.png", fx.SPARK, fx.BLOB, fx.SMOKE,
  trail.BEAM, trail.GLOW, "sprites/electric_grenade/tazed1",
  "sprites/electric_grenade/tazed2" }) do
  local found = false
  for _, p in ipairs(spec.sprites) do if p == path then found = true end end
  assert(found, "declares " .. path)
end
assert(spec.sounds[1] == "sounds/lightning/tazer_loop.wav", "declares the taze loop")

local owner = { id = 7 }
spec.on_place.on({ worm = owner, x = 100, y = 200 })
assert(mine_call and mine_call.owner == owner and mine_call.x == 100
  and mine_call.y == 200 and mine_call.radius == 16, "the mine is tracked")

spec.on_explode.on({ worm = owner, x = 100, y = 200 })
assert(blast_call, "the custom electric explosion runs")
assert(blast_call.x == 100 and blast_call.y == 200 and blast_call.owner == owner,
  "at the blast centre, owned by the mine's worm")
assert(blast_call.damage == 56 and blast_call.push == 112,
  "PX's Damage * 1.25 and the game's push (damage * 2) * 1.25")
assert(blast_call.zap == zap and blast_call.fx == fx, "the shared modules are passed")
assert(blast_call.effect and blast_call.effect.depth == wa.depth.FRONT,
  "the ring and lens draw in front")

print("electric_mine: placement, silenced blast, custom explosion and assets passed")
