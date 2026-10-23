-- PyroMan's turrets (lib/pyro_turret.lua on lib/turret.lua's body) against a
-- mocked WA: what each fires and with what, when, and how it takes damage.
--
--   lua mods/px/test_turrets.lua        (from the repo root)
local root = HIGHLANDER_ROOT or "mods/px/"
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

local M
local function mock()
  M = { worms = {}, actors = {}, shots = {}, mines = {}, arrows = {}, fires = {}, sounds = {},
    quads = {}, frame = 0, clock = 30000, solid = function() return false end,
    rng = function(lo) return lo end, handlers = {}, loads = {} }
  local function worm(id, team, alliance, x, y)
    local w = { id = id, team = team, alliance = alliance, x = x, y = y, vx = 0, vy = 0, hp = 100, facing = 1 }
    function w:ammo() return 1 end
    M.worms[#M.worms + 1] = w
    return w
  end
  M.worm = worm
  wa = {
    log = function() end,
    depth = { FRONT = 0x10000, BEHIND_TERRAIN = 0x190000 },
    msg = { START_TURN = 1 },
    math = { sin = math.sin, cos = math.cos, atan = math.atan },
    sorted = function(t)
      local keys = {}
      for k in pairs(t) do keys[#keys + 1] = k end
      table.sort(keys)
      return keys
    end,
    random = function(lo, hi) return M.rng(lo, hi) end,
    assets = { load = function(spec) M.loads[#M.loads + 1] = spec end },
    worms = { all = function() return M.worms end },
    land = { solid = function(x, y) return M.solid(x, y) end, trace = function() return nil end },
    world = {
      frame = function() return M.frame end,
      turn_clock = function() return M.clock end,
      gravity = function() return 0.2 end,
      collides = function(spec)
        for _, w in ipairs(spec.with) do
          if w == "terrain" and M.solid(spec.x // 1, spec.y // 1) then return true end
        end
        return false
      end,
    },
    draw = { quad = function(q) M.quads[#M.quads + 1] = q end },
    weapons = { launch = function(spec) M.shots[#M.shots + 1] = spec; return 1 end },
    mines = { spawn = function(spec) M.mines[#M.mines + 1] = spec; return {} end },
    arrows = { spawn = function(spec) M.arrows[#M.arrows + 1] = spec; return {} end },
    fire = { spawn = function(spec) M.fires[#M.fires + 1] = spec; return 1 end },
    on = {
      draw = function(fn) M.handlers.draw = fn end,
      turn_end = function(fn) M.handlers.turn_end = fn end,
      worm_message = function(fn) M.handlers.message = fn end,
    },
    actors = {
      spawn = function(spec)
        local a = { id = 100 + #M.actors, x = spec.x, y = spec.y, vx = 0, vy = 0, on = spec.on,
          kind = spec.kind, hit_by = spec.body and spec.body.hit_by, sounds = {} }
        function a:on_feet() return true end
        function a:in_water() return false end
        function a:warp(w) self.x, self.y = w.x, w.y end
        function a:sound(s) self.sounds[#self.sounds + 1] = s end
        function a:explode(b) self.boom = b end
        function a:despawn() self.dead = true end
        M.actors[#M.actors + 1] = a
        return a
      end,
    },
  }
  for _, name in ipairs({ "lib/turret", "lib/pyro_turret", "lib/sentry_health", "lib/shared",
    "weapons/petrol_turret", "weapons/flame_turret", "weapons/mine_turret", "weapons/auto_ballista" }) do
    package.loaded[name] = nil
  end
  require("lib/shared").fires = {}
end

-- Each sim frame: the turn clock counts down 20 ms, and the body thinks.
local function frames(a, n)
  for _ = 1, n do
    if a.dead then return end
    M.frame = M.frame + 1
    M.clock = M.clock - 20
    a.on.frame(a)
  end
end
local function start_turn(worm) M.handlers.message(worm, wa.msg.START_TURN) end
-- Frames until the turret's next shot lands in `list`: the state as it fired.
local function until_shot(a, list)
  local n = #list
  for _ = 1, 400 do
    frames(a, 1)
    if #list > n then return list[#list] end
  end
end

-- A turret of `name` planted by a red worm at x = 500 on flat ground (y 300).
local function planted(name)
  mock()
  local red = M.worm(1, 1, 0, 500, 300)
  require("weapons/" .. name).setup()
  local t = require("lib/shared")[name]
  t.place({ worm = red })
  local a = M.actors[#M.actors]
  return t, a, t.state[a.id], red
end

-- A moving blue worm `dx` right of the turret, at the turret's height.
local function enemy(dx, dy)
  local w = M.worm(2, 2, 1, 500 + dx, 300 + (dy or 0))
  w.vx = 1
  return w
end

print("PyroMan's turrets: placed, they wait for the next turn")
do
  local t, a, s = planted("mine_turret")
  local sheets = 0
  for _, l in ipairs(M.loads) do
    for _, sp in ipairs(l.sprites or {}) do
      if sp == "sprites/pyro_turrets/turrets.png" then sheets = sheets + 1 end
    end
  end
  check("it is the bundle's sheet, loaded once", sheets == 1, sheets)
  check("planted with the radius-9 drum's mask", a.x == 500 and a.y == 300)
  enemy(150)
  frames(a, 60)
  check("no ammo until a turn begins", s.ammo == 0 and #M.mines == 0, s.ammo)
  start_turn(M.worms[2])
  check("each turn gives its ammo and PX's first reload", s.ammo == 6 and s.reload_time == 20, s.reload_time)
end

print("PyroMan's turrets: targets, the running clock and the lobbed aim")
do
  local t, a, s = planted("mine_turret")
  -- The pivot is 9 + 25 above the anchor: (500, 266).
  local near_worm = enemy(20, -34)
  start_turn(M.worms[2])
  frames(a, 5)
  check("a worm inside 40 pixels of the pivot is not taken", s.tid == nil)
  near_worm.x, near_worm.y = 500 + 360, 266
  frames(a, 5)
  check("nor one beyond the sensor's 350", s.tid == nil)
  near_worm.x, near_worm.y, near_worm.vx = 500 + 150, 300, 0
  frames(a, 1) -- moved there: it walked, this once
  s.tid = nil
  frames(a, 5)
  check("nor one standing still", s.tid == nil)
  near_worm.vx = 1
  local clock = M.clock
  for _ = 1, 5 do M.frame = M.frame + 1; a.on.frame(a) end
  check("nor while the turn clock stands still", s.tid == nil and M.clock == clock)
  frames(a, 1)
  check("a moving enemy in range is taken (30% each, the RNG's)", s.tid == near_worm.id)
  M.worm(3, 3, 0, 650, 300).vx = 1
  local before = s.tid
  frames(a, 1)
  check("its own colour's worms are never targets", s.tid == before)

  -- GetShootAngle at the first flight time, 32 frames: PX's SolveBallistic.
  frames(a, 15)
  local tm, y = 32, 300 - (300 - 9 - 25)
  local rx, ry = 150 / tm, (2 * y - 0.2 * tm * tm) / (2 * tm)
  check("the shot is PX's ballistic solve", near(s.lrx, rx) and near(s.lry, ry), s.lry)
  check("its angle is from straight up, toward the worm", near(s.want, math.atan(rx, -ry)) and s.dir == 1)
  check("the head turns 0.08 rad a frame toward it", near(s.ta, 1.57 - 0.08) or near(s.ta, 1.57 + 0.08), s.ta)
end

print("PyroMan's turrets: the Mine Turret fires WA's mines, reload x1.12 a shot")
do
  local t, a, s, red = planted("mine_turret")
  enemy(150)
  start_turn(M.worms[2])
  local m = until_shot(a, M.mines)
  check("it fires a mine", m ~= nil)
  if m then
    check("PX's CMineParams: fuse 400, armed, 50 damage, radius 48",
      m.fuse == 400 and m.arm == 0 and m.damage == 50 and m.radius == 48 and not m.dud_proof)
    check("for its colour's worm", m.owner == red)
    check("from the muzzle, 10 pixels from the pivot",
      near(math.sqrt((m.x - 500) ^ 2 + (m.y - (300 - 9 - 25)) ^ 2), 10))
    check("at the solved speed less 0.1 (the RNG's 0)",
      near(math.sqrt(m.vx * m.vx + m.vy * m.vy), s.power - 0.1))
  end
  check("the first reload is 20, the next x1.12", s.reload == 20 and s.reload_time == 22, s.reload_time)
  until_shot(a, M.mines)
  check("and so on", s.reload_time == math.floor(22 * 1.12), s.reload_time)
  frames(a, 2000)
  check("six a turn, then it waits", #M.mines == 6 and s.ammo == 0, #M.mines)
  local aims = 0
  for _, snd in ipairs(a.sounds) do
    if snd == "sounds/pyro_turrets/turret_aim.wav" then aims = aims + 1 end
  end
  check("the aim sound plays at most once per 180 frames", aims >= 1 and aims <= 2200 // 180 + 1, aims)
  check("the setup sound as it plants", a.sounds[1] == "sounds/pyro_turrets/turret_setup.wav")
  start_turn(M.worms[2])
  check("the next turn reloads it", s.ammo == 6 and s.reload_time == 20)
end

print("PyroMan's turrets: land in the arc keeps it from firing")
do
  local t, a, s = planted("mine_turret")
  enemy(150)
  M.solid = function(x, y) return x > 560 and x < 580 and y < 300 end
  start_turn(M.worms[2])
  frames(a, 300)
  check("a wall in the way: nothing fired", #M.mines == 0)
  check("it tries other flight times", s.flight ~= 32, s.flight)
end

print("PyroMan's turrets: each fires its own")
do
  local t, a, s, red = planted("petrol_turret")
  enemy(150)
  start_turn(M.worms[2])
  local p = until_shot(a, M.shots)
  check("Petrol Turret: WA's Petrol Bomb, blast 15, for its worm", p and p.weapon == "stock.petrol_bomb"
    and p.missile.explosion.power == 15 and p.owner == red)
  check("Petrol Turret: six a turn", t.ammo == 6)
  check("Petrol Turret: WA's launch sound", a.sounds[2] == 44, a.sounds[2])

  t, a, s, red = planted("flame_turret")
  enemy(150)
  start_turn(M.worms[2])
  local f = until_shot(a, M.fires)
  check("Flame Turret: PX's CFireDesc", f and f.count == 0 and f.duration == 1500 and f.up_power == 1
    and f.damage == -1 and f.damage_scale == 5)
  check("Flame Turret: thrown four times as fast", f and near(math.sqrt(f.vx * f.vx + f.vy * f.vy), 4 * (s.power - 0.1)))
  check("Flame Turret: 18 a turn, its blast 45", t.ammo == 18 and t.boom.damage == 45)

  t, a, s, red = planted("auto_ballista")
  enemy(150)
  start_turn(M.worms[2])
  local r = until_shot(a, M.arrows)
  check("Auto Ballista: WA's arrow, damage 10, a quarter of gravity", r and r.damage == 10 and r.gravity_pct == 25)
  -- Aimed with a frame per 10 pixels from its centre, then the next try's.
  local dist = math.sqrt(150 * 150 + 9 * 9)
  check("Auto Ballista: a flight frame per 10 pixels", near(s.flight, (dist / 10 + 1 + 10) * 1.1), s.flight)
  check("Auto Ballista: 16 pixels to the muzzle", r and near(math.sqrt((r.x - 500) ^ 2 + (r.y - (300 - 9 - 25)) ^ 2), 16))
  check("Auto Ballista: arrows pass through it", a.hit_by and a.hit_by.arrows == nil)
end

print("PyroMan's turrets: damage, its own arrows, the death blast")
do
  local t, a, s, red = planted("auto_ballista")
  a.on.hit(a, { kind = "hit", hit_kind = 9, team = 1, damage = 10 })
  check("its own side's arrows do nothing", s.health == 50)
  a.on.hit(a, { kind = "hit", hit_kind = 9, team = 2, damage = 10 })
  check("an enemy's arrow hurts", s.health == 40)
  check("damage does not disable it, as it does a sentry", not s.disabled)
  a.on.hit(a, { kind = "blast", damage = 45 })
  check("at 0 health it is gone", a.dead and t.state[a.id] == nil)
  local boom = M.actors[#M.actors]
  check("in its colour's blast, 50 damage, from its centre",
    boom ~= a and boom.y == 300 - 9 and boom.dead)
end

print("PyroMan's turrets: drawn in its colour, darker as it is hurt, the head flipped facing left")
do
  local t, a, s = planted("petrol_turret")
  s.health, s.dir, s.ta = 25, -1, 1.0
  M.quads = {}
  M.handlers.draw()
  local base, ammo, head = M.quads[1], M.quads[2], M.quads[3]
  check("base: frame 3, the colour lifted to 128 a channel", base.frame == 3 and base.color == 0xFFFF8080)
  check("the petrol bomb in front", ammo.sprite == "sprites/pyro_turrets/ammo_petrol.png" and ammo.depth < head.depth)
  local k = 25 / 50 * 0.75 + 0.25
  check("head: the mirrored frame, dimmed by health", head.frame == 2 + 14
    and head.color == (0xFF000000 | (math.floor(255 * k) << 16) | (math.floor(128 * k) << 8) | math.floor(128 * k)),
    string.format("%d %x", head.frame, head.color))
end

if failed > 0 then error(failed .. " FAILED") end
print("PyroMan's turrets: placing, targets, lobbed aim, reloads, each weapon, damage and drawing: ALL PASS")
