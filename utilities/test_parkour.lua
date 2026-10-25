-- From the repository root: lua mods/utilities/test_parkour.lua
local root = UTILITIES_ROOT or "mods/utilities/"

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local handler, walls, floor, jumps, tick
local function setup()
  walls, floor, jumps, tick = {}, nil, 0, 0
  wa = {
    world = {frame=function()return tick end},
    msg = { FRAME_FINISH = 2, JUMP = 0x24, JUMP_UP = 0x25 },
    on = { worm_message = function(f) handler = f end },
    land = {
      -- Land at x = walls.left / walls.right, and at y = floor.
      trace = function(x0, y0, x1, y1)
        if y1 ~= y0 then
          if floor and floor <= y1 then return { hit = true, x = x0, y = floor } end
          return nil
        end
        if x1 > x0 and walls.right and walls.right <= x1 then return { hit = true, x = walls.right, y = y0 } end
        if x1 < x0 and walls.left and walls.left >= x1 then return { hit = true, x = walls.left, y = y0 } end
        return nil
      end,
    },
  }
  package.loaded["wf-lib/parkour"] = nil
  package.preload["wf-lib/parkour"] = function() return dofile(root .. "../sdk/parkour.lua") end
  dofile(root .. "features/parkour.lua")
end

local function worm(state, vx, vy)
  local w = { id = 16, turn = true, state = state, x = 100, y = 100, vx = vx or 0, vy = vy or 0, facing = 1 }
  function w:jump()
    jumps = jumps + 1
    self.state, self.vx, self.vy = "jumping", 99, 99 -- WA's take-off speed, written over
  end
  return w
end

local function frame(w) tick=tick+1;handler(w, wa.msg.FRAME_FINISH) end
local function enter(w) tick=tick+1;handler(w, wa.msg.JUMP) end
local function backspace(w) tick=tick+1;handler(w, wa.msg.JUMP_UP) end

-- Wall jump: kicks off the nearer wall, up by 2 + |vx|, away by 3 + |vx|.
setup()
walls.right = 110
local w = worm("sliding", 1.5, 2)
enter(w)
check("off a wall to the right: up and away to the left", w.vy == -3.5 and w.vx == -4.5 and w.facing == -1,
  w.vx .. "," .. w.vy)
check("from sliding: into WA's jumping state, PX's speed kept", w.state == "jumping" and jumps == 1)
w.vx, w.vy = 0, -1
enter(w)
check("not again for 15 frames", w.vx == 0 and w.vy == -1)
for _ = 1, 15 do frame(w) end
enter(w)
check("again after 15 frames, already jumping: no new take-off", w.vy == -3 and w.vx == -3 and jumps == 1)

setup()
walls.left, walls.right = 95, 112
w = worm("jumping", -2, -4)
enter(w)
check("between two walls: away from the nearer", w.vx == 5 and w.facing == 1 and w.vy == -8, w.vx .. "," .. w.vy)

setup()
w = worm("jumping")
enter(w)
check("no wall within 20 pixels: nothing", w.vx == 0 and w.vy == 0)
walls.right = 110
w = worm("standing")
enter(w)
check("on the ground: WA's own jump, not a wall jump", w.vx == 0 and jumps == 0)

setup()
walls.right = 110
w = worm("parachuting")
frame(w)
w.state = "jumping"
for _ = 1, 9 do frame(w) end
enter(w)
check("not within 10 frames of a parachute", w.vx == 0)
frame(w)
enter(w)
check("after them, it does", w.vx == -3)

-- Bunny hop: land within 30 pixels below, up by 3 and 2 more the way it faces.
setup()
floor = 125
w = worm("blasted", 1, 3)
w.facing = -1
backspace(w)
check("off the land below: up by 3, 2 more the way it faces", w.vy == -3 and w.vx == -1 and w.state == "jumping",
  w.vx .. "," .. w.vy)
setup()
floor = 140
w = worm("tumbling", 1, -2)
backspace(w)
check("no land within 30 pixels: nothing", w.vx == 1 and w.vy == -2)

setup()
floor = 120
w = worm("jump_prepare")
frame(w)
w.state = "jumping"
for _ = 1, 24 do frame(w) end
backspace(w)
check("not within 25 frames of a jump", w.vy == 0)
frame(w)
backspace(w)
check("after them, it does", w.vy == -3)

setup()
walls.right, floor = 110, 120
w = worm("jumping")
w.turn = false
enter(w)
backspace(w)
check("only the turn's worm", w.vx == 0 and w.vy == 0)

if failed > 0 then error(failed .. " FAILED") end
print("Parkour: wall jump, bunny hop, their delays and states: PASS")
