-- Kill counter, from Project X's `script_kill_counter` (Orange's Highlander
-- loads it): a numbered badge behind each worm that has killed, 1 to 9, then
-- an infinity sign. A kill is the worm whose turn it is (whatever did the
-- killing, friend or foe, as Highlander's loot), and it takes the victim's
-- own count with it: killing a worm that had 2 kills adds 3. A burst of
-- glow sparks leaves the killer.
--
-- Where this differs from the source, on purpose: the victim's count is
-- cleared, since it has passed to the killer and a worm the Reinforcement
-- brings in the dead one's place is a new worm. A PX worm died with its count.
--
-- Presentation only: the counts change in `wa.on.death`, every draw reads
-- them, nothing reaches the simulation and no roll touches WA's RNG.

-- PX: AddSpriteEx(5, PosX - 15 * TurnSide, PosY - 10, digit, 0, 0, 0.75).
local BADGE_BEHIND = 15
local BADGE_ABOVE = 10
local BADGE_SIZE = 50 * 0.75

-- PX's DoSpark(25), one PxParticle each.
local SPARKS = 25
local SPARK_LIFE = 40          -- frames
local SPARK_SPEED = { 1.5, 3.8 } -- pixels/frame, in a random direction
local SPARK_GRAVITY = 0.25 * 0.24 -- GravityFactor(0.25) of WA's gravity
local SPARK_DRAG = 0.05        -- SetAirResistance: speed lost a frame
local SPARK_JITTER = 0.2       -- SetMotionRandomness
local SPARK_SIZE = { 0.2, 0.4 } -- of the 128-pixel glow, shrinking to 0.005
local SPARK_GLOW = 128
local SPARK_ALPHA = 180

local SPRITE_DIR = "sprites/kill_counter/"
-- 0.png is PX's sign for ten and more.
local NAMES = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "kill_glow" }

local paths = {}
for i, name in ipairs(NAMES) do paths[i] = SPRITE_DIR .. name .. ".png" end
wa.assets.load({ sprites = paths })
local badge = {}
for n = 1, 10 do badge[n] = wa.sprites.key(paths[n]) end
local glow = wa.sprites.key(paths[11])

local kills = {}   -- [worm id] = count
local bursts = {}  -- { x, y, born, sparks }
local shooter      -- PX's ShootingOne: the last worm whose turn it was

wa.on.turn_start(function(event)
  if event.worm then shooter = event.worm.id end
end)

local function find(id)
  for _, worm in ipairs(wa.worms.all()) do
    if worm.id == id then return worm end
  end
end

wa.on.death(function(event)
  local victim = event.victim
  local carried = kills[victim.id] or 0
  kills[victim.id] = nil
  local killer = event.active
  if killer == nil and shooter then killer = find(shooter) end
  if killer == nil or killer.id == victim.id then return end
  kills[killer.id] = (kills[killer.id] or 0) + 1 + carried
  bursts[#bursts + 1] = { x = killer.x, y = killer.y, born = wa.world.frame() }
  wa.log(string.format("kill counter: worm %d killed worm %d, now %d",
    killer.id, victim.id, kills[killer.id]))
end)

local function lerp(a, b, t) return a + (b - a) * t end

-- Rolled at the first draw, with the draw's own random: looks only.
local function launch(burst)
  local sparks = {}
  for i = 1, SPARKS do
    local angle = wa.draw.random() * 2 * math.pi
    local speed = lerp(SPARK_SPEED[1], SPARK_SPEED[2], wa.draw.random())
    local red = math.floor(wa.draw.random() * 51)
    sparks[i] = {
      x = burst.x, y = burst.y,
      vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
      size = lerp(SPARK_SIZE[1], SPARK_SIZE[2], wa.draw.random()),
      green = { 255 - red, 80 - red },
    }
  end
  burst.sparks, burst.age = sparks, 0
end

-- One game frame of a spark's flight.
local function step(s)
  s.vx = (s.vx + (wa.draw.random() - 0.5) * SPARK_JITTER) * (1 - SPARK_DRAG)
  s.vy = (s.vy + SPARK_GRAVITY + (wa.draw.random() - 0.5) * SPARK_JITTER) * (1 - SPARK_DRAG)
  s.x, s.y = s.x + s.vx, s.y + s.vy
end

-- wa.draw.quad copies its table, so one spec is reused.
local QUAD = {
  points = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
  sprite = "", color = 0xFFFFFFFF, blend = "alpha", depth = wa.depth.FRONT,
}

local function square(x, y, size)
  local h = size / 2
  local p = QUAD.points
  p[1][1], p[1][2] = x - h, y - h
  p[2][1], p[2][2] = x + h, y - h
  p[3][1], p[3][2] = x + h, y + h
  p[4][1], p[4][2] = x - h, y + h
end

local function draw_bursts(frame, fraction)
  local live = {}
  QUAD.sprite, QUAD.blend, QUAD.visibility = glow, "add", nil
  for _, burst in ipairs(bursts) do
    local age = frame - burst.born
    if age >= 0 and age < SPARK_LIFE then
      live[#live + 1] = burst
      if not burst.sparks then launch(burst) end
      while burst.age < age do
        for _, s in ipairs(burst.sparks) do step(s) end
        burst.age = burst.age + 1
      end
      local t = (age + fraction) / SPARK_LIFE
      for _, s in ipairs(burst.sparks) do
        local green = math.floor(lerp(s.green[1], s.green[2], t))
        if green < 0 then green = 0 end
        QUAD.color = (SPARK_ALPHA << 24) | (255 << 16) | (green << 8)
        square(s.x + s.vx * fraction, s.y + s.vy * fraction,
          lerp(s.size, 0.005, t) * SPARK_GLOW)
        wa.draw.quad(QUAD)
      end
    end
  end
  bursts = live
end

wa.on.draw(function()
  local frame = wa.world.frame()
  if frame == nil then return end
  if #bursts > 0 then draw_bursts(frame, wa.draw.fraction()) end

  QUAD.blend, QUAD.color = "alpha", 0xFFFFFFFF
  for _, worm in ipairs(wa.worms.all()) do
    local n = kills[worm.id]
    if n and worm.visible ~= false then
      local side = (worm.facing and worm.facing < 0) and -1 or 1
      QUAD.sprite = badge[n > 9 and 10 or n]
      QUAD.visibility = worm
      square(worm.x - BADGE_BEHIND * side, worm.y - BADGE_ABOVE, BADGE_SIZE)
      wa.draw.quad(QUAD)
    end
  end
  QUAD.visibility = nil
end)
