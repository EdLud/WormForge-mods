-- Run from the engine checkout or the standalone mods repository.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../utilities/"
package.preload["wf-lib/tooltip"] = function() return { notice = function() end } end
local keys, selecting, speeds = {}, false, {}
local hooks = { frame = {}, start = {}, retreat = {}, stop = {} }
local selected
wa = {
  world = {
    keys = function() return keys end,
    worm_selecting = function() return selecting end,
    set_speed = function(s) speeds[#speeds + 1] = s end,
    size = function() return { w = 100, h = 100 } end,
  },
  assets = { load = function() end },
  sprites = { key = function() return 1 end },
  depth = { FRONT = 10 },
  msg = { FRAME_FINISH = 2 },
  weapons = { replace = function(spec) selected = spec end },
  on = {
    worm_message = function(f, filter) assert(filter.msgs[1] == 2); hooks.frame[#hooks.frame + 1] = f end,
    turn_start = function(f) hooks.start[#hooks.start + 1] = f end,
    turn_retreat = function(f) hooks.retreat[#hooks.retreat + 1] = f end,
    turn_end = function(f) hooks.stop[#hooks.stop + 1] = f end,
    turn_cleanup = function(f) hooks.stop[#hooks.stop + 1] = f end,
    draw = function() end,
  },
}
local ammo, delay = 2, 0
local worm = { id = 7, x = 1, y = 2, turn = true, weapon = "stock.bazooka", time_scale = 1 }
function worm:ammo(id, add)
  assert(id == "utilities.bullet_time")
  -- Adding leaves infinite (-1) alone, as the engine's does.
  if add and ammo >= 0 then ammo = ammo + add end
  return ammo
end
function worm:delay(id) return delay end
local function tick(n)
  for _ = 1, n or 1 do
    for _, f in ipairs(hooks.frame) do f(worm, 2) end
  end
end
local function fire(list) for _, f in ipairs(list) do f({ worm = worm }) end end
local function running() return speeds[#speeds] ~= nil and speeds[#speeds] < 1 end

local options = { world_speed = 40, worm_speed = 100, seconds = 20, music = false, tab = true }
local weapon = assert(loadfile(root .. "weapons/bullet_time.lua"))()
weapon.install({ id = "utilities.bullet_time", option = function(k) return options[k] end })

-- WA's worm selection has Tab: nothing.
selecting = true
keys.tab = true; tick(); keys.tab = false; tick()
assert(ammo == 2 and not running(), "Tab is WA's while it picks worms")

-- Outside it, a press starts it and spends one; the held weapon stays.
selecting = false
keys.tab = true; tick()
assert(ammo == 1 and running() and worm.weapon == "stock.bazooka", "Tab starts it, the weapon kept")
tick(10)
assert(ammo == 1, "held Tab is one press")
keys.tab = false; tick(); keys.tab = true; tick()
assert(ammo == 1, "a press while it runs spends nothing")
fire(hooks.stop)
assert(speeds[#speeds] == 1, "the turn's end stops it")

-- The retreat, a delay and no ammo refuse it.
keys.tab = false; tick()
fire(hooks.retreat)
keys.tab = true; tick(); keys.tab = false; tick()
assert(ammo == 1 and not running(), "not in the retreat")
fire(hooks.start)
delay = -1
keys.tab = true; tick(); keys.tab = false; tick()
assert(ammo == 1 and not running(), "not while blocked by its delay")
delay, ammo = 0, 0
keys.tab = true; tick(); keys.tab = false; tick()
assert(ammo == 0 and not running(), "not with none left")

-- Infinite ammo stays infinite.
ammo = -1
keys.tab = true; tick()
assert(ammo == -1 and running())
fire(hooks.stop)

-- Off in the profile: Tab does nothing, the panel still fires it.
for k in pairs(hooks) do hooks[k] = {} end
speeds, ammo = {}, 2
options.tab = false
weapon.install({ id = "utilities.bullet_time", option = function(k) return options[k] end })
keys.tab = false; tick(); keys.tab = true; tick()
assert(ammo == 2 and not running(), "the option turns Tab off")
selected.on_fire({ worm = worm })
tick() -- it eases in from full speed
assert(running(), "the panel fires it as before")
print("Bullet Time: Tab press, worm selection, retreat, delay, ammo, option and panel passed")
