-- lua mods/tests/px/test_attack_helicopter.lua
-- A round WA refuses (its object pool full) is not a shot: no sound, no
-- casing, no bullet spent, and the next try waits for the shot cadence rather
-- than the next frame. Any other launch error still reaches the brain. A
-- round's fuse ends once its line is off the map. Casings and rounds are
-- drawn, not actors.
local root = (arg[0]:match("^(.*[/\\])") or "") .. "../../px/"
package.path = root .. "?.lua;" .. package.path

local POOL_FULL = "runtime error: weapons.launch: WA's object pool is full"
local launch_error, tries, launched, sounds, actors, specs, quads
local function reset()
  launch_error, tries, launched, sounds, actors, specs, quads = nil, 0, 0, {}, {}, {}, {}
end
reset()

local next_id = 0
local function actor(spec)
  next_id = next_id + 1
  local a = { id = next_id, x = spec.x, y = spec.y, on = spec.on }
  function a:frame() end
  function a:gfx() end
  function a:gravity() end
  function a:move() end
  function a:despawn() self.dead = true end
  actors[#actors + 1] = a
  return a
end

local click
local W = 2000 -- the map's width
local FRAME, FRAC = 0, 0
local draws, missile_frames = {}, {}
wa = {
  depth = { OBJECTS = 0xE0000, BEHIND_TERRAIN = 0x190000 },
  on = {
    missile_frame = function(f) missile_frames[#missile_frames + 1] = f end,
    draw = function(f) draws[#draws + 1] = f end,
  },
  draw = {
    ribbon = function() end,
    fraction = function() return FRAC end,
    quad = function(q)
      local cx, cy = 0, 0
      for _, pt in ipairs(q.points) do cx, cy = cx + pt[1] / 4, cy + pt[2] / 4 end
      quads[#quads + 1] = { sprite = q.sprite, frame = q.frame, x = cx, y = cy, depth = q.depth }
    end,
  },
  sorted = function(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
  end,
  math = { sin = math.sin, cos = math.cos, atan = function(y, x) return math.atan(y, x) end },
  random = function(lo, hi) return lo end,
  log = function() end,
  world = {
    size = function() return { w = W, h = 1000 } end, water = function() return 900 end,
    frame = function() return FRAME end, gravity = function() return 0.1 end,
  },
  worms = { all = function() return {} end },
  land = { trace = function() return nil end },
  actors = { spawn = actor },
  sound = { play = function(_, path) sounds[#sounds + 1] = path end },
  weapons = {
    replace = function(spec) click = spec.on_click end,
    launch = function(spec)
      tries = tries + 1
      specs[#specs + 1] = spec
      if launch_error then error(launch_error) end
      launched = launched + 1
      return 1000 + launched
    end,
  },
}

local component = dofile(root .. "weapons/attack_helicopter.lua")
component.install({
  option = function(k) assert(k == "bullets"); return 17 end,
  position = { row = "F6", column = 1 },
})

local function check(what, ok) if not ok then error("FAIL: " .. what, 2) end print("  ok   " .. what) end

-- Strike at (1000, 500); the helicopter enters from the right and opens fire
-- once it is within 450 px and its 40-frame wind-up has run.
local function strike(x, y)
  click({ worm = { id = 3, kind = "worm", facing = 1, x = 1000, y = 500 }, x = x or 1000, y = y or 500 })
  for _, a in ipairs(actors) do
    if type(a.on) == "table" and a.on.frame then return a end
  end
end
local function run(body, frames, until_launched)
  for _ = 1, frames do
    FRAME = FRAME + 1
    body.on.frame(body)
    if until_launched and launched >= until_launched then return end
  end
end
-- One rendered frame: what the draw hooks put on screen, by sheet.
local function draw()
  quads = {}
  for _, f in ipairs(draws) do f() end
  local by = {}
  for _, q in ipairs(quads) do
    local k = q.sprite:match("casing") and "casing" or q.sprite:match("bullet") and "bullet" or q.sprite
    by[k] = (by[k] or 0) + 1
  end
  return by
end
local function shot_sounds()
  local n = 0
  for _, s in ipairs(sounds) do if s:find("/hks", 1, true) then n = n + 1 end end
  return n
end

print("attack helicopter: a full object pool")
do
  reset()
  launch_error = POOL_FULL
  local body = strike()
  run(body, 200)
  check("it tried to fire", tries > 0)
  check("once per shot cadence (5 frames), not every frame", tries <= 200 / 5)
  check("no shooting sound for a refused round", shot_sounds() == 0)
  check("no casing for a refused round", (draw().casing or 0) == 0)
  -- The pool frees: all 17 rounds still fly, each with its sound and casing.
  launch_error, tries = nil, 0
  local before = #actors
  run(body, 200, 17)
  check("the magazine was not spent on refusals: 17 rounds fly", launched == 17)
  check("a sound per round", shot_sounds() == 17)
  check("a casing per round, drawn, none of them an actor", draw().casing == 17)
  check("no actor per shot (the trail module's one driver at most)", #actors - before <= 1)
  run(body, 101)
  check("a casing is gone after its 100 frames", (draw().casing or 0) == 0)
end

print("attack helicopter: two at once")
do
  -- Two helicopters two frames apart fire on alternate even frames. One shot
  -- sound starts per shot cadence between them, and the sound's pick is
  -- still drawn for every round, so the draws do not change.
  reset()
  local bodies, heard, picks = {}, {}, 0
  local play, random = wa.sound.play, wa.random
  wa.sound.play = function(target, path)
    if path:find("/hks", 1, true) then heard[#heard + 1] = FRAME end
    play(target, path)
  end
  wa.random = function(lo, hi)
    if lo == 1 and hi == 3 then picks = picks + 1 end
    return random(lo, hi)
  end
  local function step(n)
    for _ = 1, n do
      FRAME = FRAME + 1
      for _, b in ipairs(bodies) do b.on.frame(b) end
    end
  end
  local function click_one()
    local before = #actors
    click({ worm = { id = 3, kind = "worm", facing = 1, x = 1000, y = 500 }, x = 1000, y = 500 })
    for i = before + 1, #actors do
      local a = actors[i]
      if type(a.on) == "table" and a.on.frame then bodies[#bodies + 1] = a end
    end
  end
  click_one()
  step(2)
  click_one()
  for _ = 1, 400 do if launched >= 34 then break end step(1) end
  wa.sound.play, wa.random = play, random
  check("both magazines fly: 34 rounds", launched == 34)
  check("a pick drawn for every round", picks == 34)
  local apart = true
  for i = 2, #heard do if heard[i] - heard[i - 1] < 4 then apart = false end end
  check("no two shot sounds within one shot cadence", apart)
  check("fewer shot sounds than rounds, as many as one helicopter's", #heard < 34 and #heard >= 17)
end

print("attack helicopter: any other launch error")
do
  reset()
  launch_error = "runtime error: weapons.launch: bad owner"
  local body = strike()
  local ok, err = pcall(run, body, 200)
  check("reaches the brain", not ok and tostring(err):find("bad owner", 1, true) ~= nil)
end

print("attack helicopter: a round's fuse")
do
  -- The helicopter hovers just short of its target. A target a little below
  -- it on a narrow map: the rounds fly steeply down and right, and their line
  -- leaves by the right side well before PX's 3000 ms.
  reset()
  W = 1100
  local body = strike(1000, -200)
  run(body, 200)
  W = 2000
  local first = specs[1]
  check("a round flies", first ~= nil)
  local fuse = first.missile.fuse
  local dx, dy = 999 - first.x, -200 - first.y -- wa.random(-1, 1) gives -1 here
  local vx = dx / math.sqrt(dx * dx + dy * dy) * 35
  local exit = (1100 - first.x) / vx
  check("it bursts just past the right side, not after 3 s", fuse < 3000)
  check("only once its line is off the map", fuse >= exit * 20 and fuse <= (exit + 5) * 20)
  -- Straight down, the line never reaches a side: PX's full fuse.
  reset()
  body = strike(1000, 900)
  run(body, 200)
  local longest = 0
  for _, sp in ipairs(specs) do longest = math.max(longest, sp.missile.fuse) end
  check("a round whose line stays over the map keeps up to 3000 ms", longest == 3000)
end

print("attack helicopter: a round, drawn")
do
  reset()
  local body = strike(1000, 500)
  run(body, 200, 1)
  local id = 1000 + launched
  local m = { id = id, phase = "post", x = 500, y = 100, vx = -20, vy = 30 }
  for _, f in ipairs(missile_frames) do f(m) end
  m.x, m.y = 480, 130
  for _, f in ipairs(missile_frames) do f(m) end
  FRAC = 0.5
  check("WA's own sprite is hidden", (function()
    local pre = { id = id, phase = "pre", x = 480, y = 130, vx = -20, vy = 30, sprite = 7 }
    for _, f in ipairs(missile_frames) do f(pre) end
    return pre.sprite == 0
  end)())
  draw()
  local b
  for _, q in ipairs(quads) do if q.sprite:match("bullet") then b = q end end
  check("the round is drawn", b ~= nil)
  check("stepped on by WA's interpolation", math.abs(b.x - 470) < 1e-6 and math.abs(b.y - 145) < 1e-6)
  check("in front of the objects", b.depth == wa.depth.OBJECTS - 1)
  FRAC = 0
  FRAME = FRAME + 2
  check("a round whose frames stopped is not drawn", (draw().bullet or 0) == 0)
end

print("ALL PASS")
