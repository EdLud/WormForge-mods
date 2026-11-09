-- Run from the engine checkout or the standalone mods repository.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../utilities/"
package.preload["wf-lib/tooltip"] = function() return { notice = function() end } end
local keys, selecting, speeds = {}, false, {}
local hooks = { frame = {}, start = {}, retreat = {}, stop = {} }
local selected
-- wa.hud.tray as the engine keeps it: one entry per team and weapon, and an
-- unlit one dropped (`tray_tick`) once its team has none.
local tray = {}
local function tray_add(spec)
  for _, e in ipairs(tray) do
    if e.team == spec.team and e.weapon == spec.weapon then return e end
  end
  local e = { weapon = spec.weapon, team = spec.team, key = spec.key, lit = false, open = true }
  function e:set(t)
    if not self.open then return false end
    for k, v in pairs(t) do
      if v == false and k ~= "lit" then v = nil end
      self[k] = v
    end
    return true
  end
  function e:is_open() return self.open end
  tray[#tray + 1] = e
  return e
end
wa = {
  hud = { tray = { add = function(spec) return tray_add(spec) end } },
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
local worm = { id = 7, team = 1, x = 1, y = 2, turn = true, weapon = "stock.bazooka", time_scale = 1 }
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

-- The tray: the team's cell while it has any, lit with the time left while
-- it runs, dropped once the last unit's run ends.
local function tray_tick()
  for i = #tray, 1, -1 do
    local e = tray[i]
    if not e.lit and ammo == 0 then e.open = false; table.remove(tray, i) end
  end
end
local function tick_all(n) for _ = 1, n or 1 do tick(); tray_tick() end end
for k in pairs(hooks) do hooks[k] = {} end
tray, speeds, ammo, delay = {}, {}, 0, 0
keys.tab = false
options.tab = true
weapon.install({ id = "utilities.bullet_time", option = function(k) return options[k] end })
tick_all()
assert(#tray == 0, "no cell without any")
ammo = 1
tick_all()
assert(#tray == 1 and tray[1].key == "Tab" and tray[1].team == 1 and not tray[1].lit, "the team's cell, Tab under it")
tick_all(5)
assert(#tray == 1, "one cell, however often it is seen")
keys.tab = true; tick_all()
local e = tray[1]
assert(ammo == 0 and e and e.lit and e.progress < 1, "lit with the time left; the last unit spent")
local before = e.progress
tick_all(50)
assert(e.open and e.progress < before, "the bar runs down, and lit holds it with none left")
fire(hooks.stop); tray_tick()
assert(not e.open and #tray == 0, "its run over and none left: dropped")

-- Off in the profile: Tab does nothing, the panel still fires it.
for k in pairs(hooks) do hooks[k] = {} end
tray = {}
speeds, ammo = {}, 2
options.tab = false
weapon.install({ id = "utilities.bullet_time", option = function(k) return options[k] end })
keys.tab = false; tick(); keys.tab = true; tick()
assert(ammo == 2 and not running(), "the option turns Tab off")
selected.on_fire({ worm = worm })
tick() -- it eases in from full speed
assert(running(), "the panel fires it as before")
assert(#tray == 0, "no tray without Tab")
print("Bullet Time: Tab press, worm selection, retreat, delay, ammo, tray, option and panel passed")
