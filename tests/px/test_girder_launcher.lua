-- lua mods/tests/px/test_girder_launcher.lua
-- A girder that would trap a worm (the shooter beside a wall) is refused at
-- the fire press, before WA counts the shot; at impact it is never laid.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../px/"
package.path = root .. "?.lua;" .. package.path

local fire_hook, trace_result, stamps, sounds, nearby, worms, launched
local function reset()
  fire_hook, trace_result, stamps, sounds, nearby, worms, launched = nil, {}, {}, {}, {}, {}, {}
end
reset()
package.loaded["wf-lib/holds"] = { PX_POSTURE = {} }
package.loaded["lib/turret"] = { projectile_target = function() end }
wa = {
  msg = { FIRE_WEAPON = 0x26 },
  on = {
    worm_message = function(fn, spec)
      assert(spec.msgs[1] == wa.msg.FIRE_WEAPON and #spec.msgs == 1)
      fire_hook = fn
    end,
    missile_frame = function() end,
    draw = function() end,
  },
  world = {
    trace = function(t) trace_result.query = t; return trace_result.hit end,
    electrical_nearby = function() return nearby end,
  },
  worms = { all = function() return worms end },
  sound = { play = function(worm, id) sounds[#sounds + 1] = id end },
  land = { stamp = function(s) stamps[#stamps + 1] = s end },
  weapons = { launch = function(spec) launched[#launched + 1] = spec; return #launched end },
}

local weapon = dofile(root .. "weapons/girder_launcher.lua")

local function check(what, ok) if not ok then error("FAIL: " .. what, 2) end print("  ok   " .. what) end

local function shooter(x, y, facing)
  local w = { id = 17, kind = "worm", x = x, y = y, hp = 100, turn = true, weapon = "px.girder_launcher",
    aim = 0.5, facing = facing or 1 }
  function w:hurt(n) self.hurt_by = n end
  return w
end

print("girder launcher: the fire press")
do
  -- Aim level, facing right: WA starts the shell 14 px out, at (114, 100).
  reset(); weapon.setup()
  local w = shooter(100, 100); worms = { w }
  trace_result.hit = { hit = true, x = 116, y = 100 }
  check("a wall 16 px ahead: the girder would cover the shooter, the fire is eaten", fire_hook(w) == "eat")
  check("from 14 px out along the aim", trace_result.query.x0 == 114 and math.abs(trace_result.query.y0 - 100) < 1e-9)
  check("WA's can't-fire sound", sounds[1] == 120)
  trace_result.hit = { hit = true, x = 140, y = 100 }
  check("a wall 40 px ahead: the girder lies clear of the shooter, it fires", fire_hook(w) == nil)
  trace_result.hit = nil
  check("nothing in reach: it fires", fire_hook(w) == nil)
  trace_result.hit = { hit = true, x = 116, y = 100, obj = { kind = "worm", id = 3 } }
  check("a body in the way: it is pushed, no girder, it fires", fire_hook(w) == nil)
  trace_result.hit = { hit = true, x = 120, y = 100, starts_solid = true }
  check("starting in the land: the girder lands at the start, eaten", fire_hook(w) == "eat")
  -- Aiming straight up beside an overhang: the bar stands on the worm's head.
  w.aim = 1
  trace_result.hit = { hit = true, x = 100, y = 78 }
  check("an overhang 22 px above: covers the head, eaten", fire_hook(w) == "eat")
  local other = shooter(160, 100); other.id, other.turn = 4, false
  worms = { w, other }
  w.aim = 0.5
  trace_result.hit = { hit = true, x = 150, y = 100 }
  check("a wall where another worm stands: the girder would wall that worm in, eaten", fire_hook(w) == "eat")
  nearby = { other }
  check("that worm within 20 px of where it stops: pushed, not walled in, it fires", fire_hook(w) == nil)
  w.turn = false
  trace_result.hit = { hit = true, x = 116, y = 100 }
  nearby = {}
  check("not the turn's worm: left to WA", fire_hook(w) == nil)
end

print("girder launcher: impact")
do
  reset(); weapon.setup()
  local w = shooter(100, 100); worms = { w }
  weapon.definition.on_fire({ worm = w, x = 114, y = 100, vx = 10, vy = 0 })
  weapon.definition.on_explode({ missile = 1, x = 115, y = 100 })
  check("a forecast miss: the girder is not laid over the shooter", #stamps == 0)
  check("and WA's can't-fire sound", sounds[1] == 120)
  weapon.definition.on_fire({ worm = w, x = 114, y = 100, vx = 10, vy = 0 })
  weapon.definition.on_explode({ missile = 2, x = 150, y = 100 })
  check("clear of every worm: the girder is laid", #stamps == 1 and stamps[1].x == 150)
  local other = shooter(158, 100); other.id = 4
  worms = { w, other }; nearby = { other }
  weapon.definition.on_fire({ worm = w, x = 114, y = 100, vx = 10, vy = 0 })
  weapon.definition.on_explode({ missile = 3, x = 150, y = 100 })
  check("a worm where it stops is pushed and hurt, no girder", #stamps == 1 and other.hurt_by == 3)
end

print("ALL PASS")
