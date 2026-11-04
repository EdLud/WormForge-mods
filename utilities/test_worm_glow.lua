-- From the repository root: lua mods/utilities/test_worm_glow.lua
local path = "mods/utilities/features/worm_glow.lua"

local function run(pad)
  local hooks, worms, loaded = {}, {}, nil
  local env = setmetatable({ wa = {
    on = setmetatable({}, { __index = function(_, name)
      assert(name == "draw", name)
      return function(fn) hooks[name] = fn end
    end }),
    assets = { load = function(spec) loaded = spec end },
    worms = { all = function() return worms end },
  } }, { __index = _G })
  local install = assert(loadfile(path, "t", env))()
  local options = { strength = 40, radius = 5, pad = pad or 0, gain = 250, red = 255, green = 128, blue = 0 }
  install({ option = function(key) return assert(options[key], key) end })
  return { hooks = hooks, worms = worms, loaded = loaded }
end

-- WA's poses loaded with the match, and the glow's shape: pad 0 leaves it
-- to the engine (twice the radius and one).
local on = run()
assert(on.loaded.wa_sprites[1] == "worm")
local shape = on.loaded.worm_glow
assert(shape.radius == 5 and shape.pad == nil and shape.gain == 2.5)
assert(run(9).loaded.worm_glow.pad == 9)

-- Every untinted worm glows white; a pack's own tint is kept.
local plain, zombie = {}, { tint = 0x60FF60 }
on.worms[1], on.worms[2] = plain, zombie
on.hooks.draw()
assert(plain.tint.color == 0xFFFFFF and plain.tint.glow == 0.4)
assert(plain.tint.glow_color == 0xFF8000, "the glow in the options' colour, the body WA's")
assert(zombie.tint == 0x60FF60, "a pack's own tint is kept")
-- Cleared by its pack, the worm glows again.
zombie.tint = nil
on.hooks.draw()
assert(zombie.tint.glow == 0.4)
print("worm glow: ok")
