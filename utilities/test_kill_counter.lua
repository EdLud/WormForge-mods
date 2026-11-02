-- From the repository root: lua mods/utilities/test_kill_counter.lua
local path = "mods/utilities/features/kill_counter.lua"
local frame, hooks, quads, worms = 100, {}, {}, {}
local loaded
local env = setmetatable({ wa = {
  depth = { FRONT = 0x10000 },
  on = setmetatable({}, { __index = function(_, name)
    assert(name == "death" or name == "turn_start" or name == "draw", name)
    return function(fn) hooks[name] = fn end
  end }),
  assets = { load = function(spec) loaded = spec end },
  sprites = { key = function(p) return "core.utilities:" .. p end },
  worms = { all = function() return worms end },
  world = { frame = function() return frame end },
  draw = {
    -- The engine copies the spec, which the feature reuses.
    quad = function(q)
      quads[#quads + 1] = {
        sprite = q.sprite, blend = q.blend, visibility = q.visibility,
        points = { { q.points[1][1] }, nil, { q.points[3][1] } },
      }
    end,
    random = function() return 0.5 end,
    fraction = function() return 0 end,
  },
  log = function() end,
  random = function() error("gameplay RNG used") end,
  actors = setmetatable({}, { __index = function() error("physics used") end }),
} }, { __index = _G })
assert(loadfile(path, "t", env))()
assert(#loaded.sprites == 11)

local function worm(id, x, facing)
  return { id = id, x = x, y = 200, facing = facing, visible = true }
end
local a, b, c, d = worm(1, 100, 1), worm(2, 300, -1), worm(17, 500, 1), worm(18, 700, 1)
worms = { a, b, c, d }

local function draw()
  quads = {}
  hooks.draw()
  local badges, sparks = {}, 0
  for _, q in ipairs(quads) do
    if q.blend == "add" then
      sparks = sparks + 1
    else
      local cx = (q.points[1][1] + q.points[3][1]) / 2
      badges[#badges + 1] = { sprite = q.sprite:match("kill_counter/(%w+)%.png"), x = cx, worm = q.visibility }
    end
  end
  return badges, sparks
end

local badges, sparks = draw()
assert(#badges == 0 and sparks == 0, "no kills, nothing drawn")

-- Worm 1's turn: it kills worm 17, behind it (facing right) a 1.
hooks.turn_start({ worm = a })
hooks.death({ victim = c, active = a })
badges, sparks = draw()
assert(#badges == 1 and badges[1].sprite == "1" and badges[1].x == 85 and badges[1].worm == a)
assert(sparks == 25, "one burst of 25 sparks")

-- A worm dying on its own turn credits nobody.
hooks.death({ victim = a, active = a })
badges = draw()
assert(#badges == 0, "the dead worm's count is gone with it")

-- Worm 2 (facing left) kills 18, then 18 again once it has a kill: 1 + (1 + 1).
hooks.turn_start({ worm = b })
hooks.death({ victim = d, active = b })
hooks.death({ victim = c, active = d }) -- 18 credited with 17's kill
hooks.death({ victim = d, active = b })
badges = draw()
for _, badge in ipairs(badges) do
  if badge.worm == b then
    assert(badge.sprite == "3" and badge.x == 315, "b: " .. badge.sprite .. " at " .. badge.x)
  end
end
hooks.death({ victim = worm(3, 0, 1), active = b })
-- Between turns, the last worm whose turn it was (PX's ShootingOne).
hooks.death({ victim = worm(4, 0, 1), active = nil })
badges = draw()
assert(#badges == 1 and badges[1].sprite == "5", tostring(badges[1] and badges[1].sprite))

-- Ten and more: PX's infinity sign (its 0.png).
for id = 5, 10 do hooks.death({ victim = worm(id, 0, 1), active = b }) end
badges = draw()
assert(badges[1].sprite == "0")

-- A hidden worm hides its badge.
b.visible = false
badges = draw()
assert(#badges == 0)

-- The sparks are gone after their 40 frames.
frame = frame + 40
b.visible = true
local _, left = draw()
assert(left == 0)
print("kill counter: ok")
