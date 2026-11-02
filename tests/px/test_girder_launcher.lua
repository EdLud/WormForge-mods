-- lua mods/tests/px/test_girder_launcher.lua
-- A girder that would hold a worm inside new land (the shooter beside a
-- wall) is laid deeper into the land, or hits that worm instead.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../px/"
package.path = root .. "?.lua;" .. package.path

local stamps, sounds, nearby, worms, launched, logs, solid
local function reset()
  stamps, sounds, nearby, worms, launched, logs = {}, {}, {}, {}, {}, {}
  solid = function() return false end
end
reset()
package.loaded["wf-lib/holds"] = { PX_POSTURE = {} }
package.loaded["lib/turret"] = { projectile_target = function() end }
wa = {
  on = {
    worm_message = function() error("the Girder Launcher hooks no worm message") end,
    missile_frame = function() end,
    draw = function() end,
  },
  -- WA's sine table is 16.16.
  math = {
    sin = function(x) return math.floor(math.sin(x) * 65536 + 0.5) / 65536 end,
    cos = function(x) return math.floor(math.cos(x) * 65536 + 0.5) / 65536 end,
  },
  world = { electrical_nearby = function() return nearby end },
  worms = { all = function() return worms end },
  sound = { play = function(worm, id) sounds[#sounds + 1] = id end },
  land = {
    stamp = function(s) stamps[#stamps + 1] = s end,
    solid = function(x, y) return solid(x, y) end,
  },
  weapons = { launch = function(spec) launched[#launched + 1] = spec; return #launched end },
  log = function(line) logs[#logs + 1] = line end,
}

local weapon = dofile(root .. "weapons/girder_launcher.lua")

local function check(what, ok) if not ok then error("FAIL: " .. what, 2) end print("  ok   " .. what) end

local function shooter(x, y, facing)
  local w = { id = 17, kind = "worm", x = x, y = y, hp = 100, turn = true, weapon = "px.girder_launcher",
    aim = 0.5, facing = facing or 1 }
  function w:hurt(n) self.hurt_by = n end
  return w
end

-- The mock's launch numbers missiles in order.
local function shoot(_, w, vx, vy, x, y)
  weapon.definition.on_fire({ worm = w, x = w.x, y = w.y, vx = vx, vy = vy })
  weapon.definition.on_explode({ missile = #launched, x = x, y = y })
end

print("girder launcher: where the girder is laid")
do
  reset(); weapon.setup()
  local w = shooter(100, 100); worms = { w }
  solid = function(x) return x >= 162 end
  shoot(1, w, 10, 0, 150, 100)
  check("clear of every worm: laid where the shell stops, along its flight",
    #stamps == 1 and stamps[1].x == 150 and stamps[1].y == 100 and stamps[1].frame == 8)
  check("drawn over the land, no buried blend", stamps[1].buried == nil)
  check("with the impact sound", sounds[#sounds] == "sounds/girder_launcher/mgirder_impact.wav")
  -- Beside a wall (land from x 106): at the impact its back half would be
  -- land through the shooter, so it goes into the wall until its back end
  -- (11 px behind its centre pixel) is a pixel clear of his shape (x 96..104).
  solid = function(x) return x >= 106 end
  shoot(2, w, 10, 0, 105, 100)
  check("the shooter beside a wall: laid deeper, clear of him",
    #stamps == 2 and stamps[2].x == 117 and stamps[2].y == 100 and w.hurt_by == nil)
  check("that is logged", logs[#logs]:find("12px deeper", 1, true) ~= nil)
  -- The engine plots it around the pixel its position rounds down to: at
  -- 116.6 that is 116, whose back end (105) touches his shape's margin, so it
  -- goes a pixel deeper. Rounded to nearest (117) it looked clear.
  solid = function(x) return x >= 117 end
  shoot(5, w, 10, 0, 116.6, 100)
  check("a fractional impact is checked where the engine plots it",
    #stamps == 3 and math.abs(stamps[3].x - 117.6) < 1e-9 and logs[#logs]:find("1px deeper", 1, true) ~= nil)
  table.remove(stamps)
  -- Aiming up under an overhang (land up to y 84): it goes up into it, its
  -- lower end a pixel clear of his shape's top row (y 91).
  solid = function(_, y) return y <= 84 end
  shoot(3, w, 0, -10, 100, 85)
  check("an overhang just above the head: laid up in it",
    #stamps == 3 and stamps[3].x == 100 and stamps[3].y == 78 and stamps[3].frame == 0)
  -- No land ahead to go into: the shooter takes the shell's hit instead.
  solid = function() return false end
  shoot(4, w, 10, 0, 105, 100)
  check("no depth clears the shooter: he is hit and pushed, no girder",
    #stamps == 3 and w.hurt_by == 3 and w.vx == 2.5 and w.vy == 0)
  check("that is logged too", logs[#logs]:find("clears worm 17", 1, true) ~= nil)
end

print("girder launcher: struck bodies")
do
  reset(); weapon.setup()
  local w = shooter(100, 100)
  local other = shooter(158, 100); other.id, other.turn = 4, false
  worms = { w, other }; nearby = { other }
  shoot(1, w, 10, 0, 150, 100)
  check("a worm where it stops is pushed and hurt, no girder", #stamps == 0 and other.hurt_by == 3)
  -- Beside a wall, the shooter is within 20 px of where it stops.
  nearby = { w }
  other.x = 1000
  solid = function(x) return x >= 106 end
  shoot(2, w, 10, 0, 105, 100)
  check("the shooter is never the struck body", #stamps == 1 and stamps[1].x == 117 and w.hurt_by == nil)
end

print("ALL PASS")
