-- Hazardous Sentries (components/hazardous_sentries.lua, lib/hazard_spot.lua) against a
-- mocked WA: where the neutral sentries go, their own settings, and how no team owns them.
--
--   lua mods/tests/px/test_hazardous_sentries.lua        (from the engine repo root)
local root = HIGHLANDER_ROOT or ((arg[0]:match("^(.*[/\\])") or "") .. "../../px/")
package.path = root .. "?.lua;" .. package.path

local failed = 0
local function check(name, ok, detail)
  if ok then return end
  failed = failed + 1
  print("  FAIL " .. name .. (detail ~= nil and ("   [" .. tostring(detail) .. "]") or ""))
end

local MODULES = { "lib/turret", "lib/pyro_turret", "lib/sentry_health", "lib/sentry_mask", "lib/shared",
  "lib/electrical", "lib/weapon", "lib/laser", "lib/hazard_spot", "components/hazardous_sentries",
  "weapons/sentry_gun", "weapons/sentry_laser", "weapons/petrol_turret", "weapons/flame_turret",
  "weapons/mine_turret", "weapons/auto_ballista" }

local M
local function mock(solid)
  M = { worms = {}, actors = {}, bullets = {}, shots = {}, mines = {}, arrows = {}, fires = {},
    quads = {}, frame = 0, clock = 30000, solid = solid or function(_, y) return y > 300 end,
    picks = {}, rng = function(lo) return lo end, handlers = { turn_start = {}, turn_end = {} }, loads = {}, also = {} }
  local function worm(id, team, alliance, x, y)
    local w = { id = id, team = team, alliance = alliance, x = x, y = y, vx = 0, vy = 0, hp = 100, facing = 1 }
    function w:ammo() return 1 end
    M.worms[#M.worms + 1] = w
    return w
  end
  M.worm = worm
  local function solid_at(x, y) return M.solid(x // 1, y // 1) end
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
    random = function(lo, hi)
      M.picks[#M.picks + 1] = { lo, hi }
      return M.rng(lo, hi)
    end,
    sound = { play = function(target, name) if target.sounds then target.sounds[#target.sounds + 1] = name end end },
    assets = { load = function(spec) M.loads[#M.loads + 1] = spec end },
    worms = { all = function() return M.worms end },
    missiles = { all = function() return M.missiles or {} end },
    mines = { all = function() return M.map_mines or {} end,
      spawn = function(spec) M.mines[#M.mines + 1] = spec; return {} end },
    land = {
      solid = function(x, y) return solid_at(x, y) end,
      trace = function(x0, y0, x1, y1)
        local n = math.max(1, math.max(math.abs(x1 - x0), math.abs(y1 - y0)) // 1)
        for i = 0, n do
          local x, y = x0 + (x1 - x0) * i / n, y0 + (y1 - y0) * i / n
          if solid_at(x, y) then return { hit = true, x = x, y = y } end
        end
      end,
    },
    world = {
      frame = function() return M.frame end,
      turn_clock = function() return M.clock end,
      gravity = function() return 0.2 end,
      size = function() return { w = 1000, h = 600 } end,
      water = function() return 560 end,
      -- a pixel walk of the line, as the engine's sweep with radius 0
      trace = function(spec)
        local n = math.max(1, math.max(math.abs(spec.x1 - spec.x0), math.abs(spec.y1 - spec.y0)) // 1)
        local function at(i)
          return spec.x0 + (spec.x1 - spec.x0) * i / n, spec.y0 + (spec.y1 - spec.y0) * i / n
        end
        local out, from = { hit = false }, 0
        if solid_at(at(0)) then
          out.starts_solid = true
          local i = 1
          while i <= n and solid_at(at(i)) do i = i + 1 end
          if i > n then return out end
          out.left_x, out.left_y = at(i)
          from = i
        end
        for i = from + 1, n do
          if solid_at(at(i)) then
            out.hit = true
            out.x, out.y = at(i - 1)
            out.y = out.y + 0.996 -- the last free centre, to a fraction of the step
            return out
          end
        end
        if out.starts_solid then return out end
      end,
      collides = function(spec)
        local r = spec.radius or 0
        for _, kind in ipairs(spec.with) do
          if kind == "terrain" then
            for dy = -r, r do
              for dx = -r, r do
                if dx * dx + dy * dy <= r * r and solid_at(spec.x + dx, spec.y + dy) then return true end
              end
            end
          elseif kind == "worms" then
            for _, w in ipairs(M.worms) do
              if (w.x - spec.x) ^ 2 + (w.y - spec.y) ^ 2 <= (r + 6) ^ 2 then return true end
            end
          end
        end
        return false
      end,
    },
    draw = { quad = function(q) M.quads[#M.quads + 1] = q end, ribbon = function() end },
    weapons = {
      launch = function(spec) M.shots[#M.shots + 1] = spec; return 1 end,
      fire_bullet = function(spec) M.bullets[#M.bullets + 1] = spec end,
      replace = function() end,
    },
    arrows = { spawn = function(spec) M.arrows[#M.arrows + 1] = spec; return {} end },
    fire = { spawn = function(spec) M.fires[#M.fires + 1] = spec; return 1 end },
    on = {
      draw = function(fn) M.handlers.draw = M.handlers.draw or {}; table.insert(M.handlers.draw, fn) end,
      turn_end = function(fn) table.insert(M.handlers.turn_end, fn) end,
      turn_start = function(fn) table.insert(M.handlers.turn_start, fn) end,
      worm_message = function(fn) M.handlers.message = M.handlers.message or {}; table.insert(M.handlers.message, fn) end,
    },
    actors = {
      spawn = function(spec)
        local a = { id = 100 + #M.actors, x = spec.x, y = spec.y, vx = 0, vy = 0, on = spec.on,
          owner = spec.owner, kind = "actor", hit_by = spec.body and spec.body.hit_by, sounds = {} }
        function a:on_feet() return true end
        function a:in_water() return false end
        function a:warp(w) self.x, self.y = w.x, w.y end
        function a:explode(b) self.boom = b end
        function a:remove() self.dead = true end
        function a:move() end
        function a:frame() end
        M.actors[#M.actors + 1] = a
        return a
      end,
    },
  }
  dofile(root .. "../tests/brush_mock.lua")(wa)
  for _, name in ipairs(MODULES) do package.loaded[name] = nil end
  require("lib/shared").fires = {}
  -- the pack's loader, as far as the add-on reaches it: the modules it asks for, set up
  package.loaded["components/loader"] = {
    also = function(path) M.also[#M.also + 1] = path end,
    place = function() return {} end,
    load = function() for _, path in ipairs(M.also) do require(path).setup() end end,
  }
end

local DEFAULTS = {
  sentry_gun = 0, sentry_gun_health = 50, sentry_gun_ammo = 20, sentry_gun_damage = 2, sentry_gun_push_pct = 100,
  sentry_laser = 0, sentry_laser_health = 35, tracking_pct = 100, aim_ahead = false,
}
for _, key in ipairs({ "petrol_turret", "flame_turret", "mine_turret", "auto_ballista" }) do
  DEFAULTS[key], DEFAULTS[key .. "_health"], DEFAULTS[key .. "_ammo"] = 0, 50, 6
  DEFAULTS[key .. "_fire_rate"], DEFAULTS[key .. "_fire_increase_pct"] = 400, 12
end
local function install(options)
  local ctx = { weapons = options.weapons or {}, option = function(key)
    local v = options[key]
    if v == nil then v = DEFAULTS[key] end
    assert(v ~= nil, "no option " .. key)
    return v
  end }
  require("components/hazardous_sentries").install(ctx)
end
local function turn_start(worm)
  for _, fn in ipairs(M.handlers.turn_end) do fn({ worm = worm }) end
  for _, fn in ipairs(M.handlers.turn_start) do fn({ worm = worm }) end
  for _, fn in ipairs(M.handlers.message or {}) do fn(worm, wa.msg.START_TURN) end
end
local function frames(a, n)
  for _ = 1, n do
    if a.dead then return end
    M.frame = M.frame + 1
    M.clock = M.clock - 20
    a.on.frame(a)
  end
end

print("Hazardous Sentries: the ground under every column, through a cavern")
do
  -- a ceiling to y 40, a ledge from 200 to 220, the floor below 300
  mock(function(_, y) return y <= 40 or (y >= 200 and y <= 220) or y > 300 end)
  local ground = require("lib/hazard_spot").ground()
  local at = {}
  for _, p in ipairs(ground) do
    if p[1] == 500 then at[#at + 1] = p[2] end
  end
  check("two surfaces in a column, top to bottom", #at == 2 and at[1] == 199 and at[2] == 300,
    table.concat(at, ","))
  check("columns 5 px apart, the box inside the map", ground[1][1] == 25 and ground[#ground][1] == 975)
end

print("Hazardous Sentries: a 50 by 50 box, clear of land, worms and each other")
do
  -- flat floor below 300, a pillar at x 600..619 from the top down
  mock(function(x, y) return y > 300 or (x >= 600 and x < 620) end)
  local spot = require("lib/hazard_spot")
  local ground = spot.ground()
  local index_of = {}
  for i, p in ipairs(ground) do index_of[p[1]] = i end
  check("no ground in the pillar", index_of[600] == nil and index_of[615] == nil)
  local taken = {}
  M.rng = function() return index_of[590] end
  local x, y = spot.find(ground, taken)
  check("the box can't touch the pillar: the first that fits is past it", x == 645 and y == 300, tostring(x))
  M.rng = function() return index_of[650] end
  x = spot.find(ground, taken)
  check("100 px from the hazard before it", x == 745, tostring(x))
  M.worm(1, 1, 0, 800, 290)
  M.rng = function() return index_of[760] end
  x = spot.find(ground, taken)
  check("75 px from a worm", x == 875, tostring(x))
  check("one random pick of where to start, for each", #M.picks == 3 and M.picks[1][1] == 1 and M.picks[1][2] == #ground)
  M.rng = function() return 1 end
  local full = {}
  for i = 1, 40 do full[i] = { (i - 1) * 25, 275 } end
  check("nil when nothing fits", spot.find(ground, full) == nil)
end

-- Each hazard body's turret and state, as the Tazer's arc finds them.
local function hazards()
  local out = {}
  for _, obj in ipairs(require("lib/electrical").special_targets()) do
    if obj.s.alliance == require("lib/turret").NEUTRAL then out[#out + 1] = obj end
  end
  return out
end

print("Hazardous Sentries: placed at the first turn, grey, of no team, on their own settings")
do
  mock()
  local red = M.worm(1, 1, 0, 100, 300)
  install({ sentry_gun = 2, sentry_gun_health = 80, sentry_gun_damage = 7, petrol_turret = 1, petrol_turret_ammo = 9 })
  local shared = require("lib/shared")
  check("only the turrets it places are set up", #M.also == 2
    and M.also[1] == "weapons/sentry_gun" and M.also[2] == "weapons/petrol_turret")
  check("the Sentry Gun's art loaded for a match that doesn't place it", #M.loads >= 1
    and M.loads[#M.loads].gpu_prefix == "sprites/sentry_gun/turret_")
  check("nothing placed before the first turn", #M.actors == 0)
  turn_start(red)
  local placed = hazards()
  check("three placed", #placed == 3, #placed)
  turn_start(red)
  check("once a round", #hazards() == 3)
  local guns, petrol = 0, nil
  for _, h in ipairs(placed) do
    check("owned by no team, no planter", h.s.body.owner == "none" and h.s.planter == nil)
    if h.t.kind == "hazard_sentry" then
      guns = guns + 1
      check("the add-on's health and damage", h.s.max_health == 80 and h.t.damage == 7)
    elseif h.t.kind == "hazard_petrol_turret" then
      petrol = h
    end
  end
  check("two guns and a petrol turret", guns == 2 and petrol and petrol.s.ammo == 9)
  check("the weapons keep their own settings", shared.sentry_gun.health == 50 and shared.sentry_gun.damage == 2
    and shared.petrol_turret.ammo == 6)
  local grey = 0
  for _, fn in ipairs(M.handlers.draw) do
    M.quads = {}
    fn()
    for _, q in ipairs(M.quads) do
      if q.sprite == "sprites/sentry_gun/turret_head.png" or q.frame == require("lib/pyro_turret").FRAMES.petrol.base then
        if q.color == 0xFF000000 | require("lib/turret").GREY then grey = grey + 1 end
      end
    end
  end
  check("drawn grey", grey == 3, grey)
end

print("Hazardous Sentries: one Tracking speed and Aim ahead for all of them, not the weapons'")
do
  mock()
  local red = M.worm(1, 1, 0, 100, 300)
  install({ sentry_gun = 1, mine_turret = 1, tracking_pct = 300, aim_ahead = true })
  turn_start(red)
  local gun, mine
  for _, h in ipairs(hazards()) do
    if h.t.kind == "hazard_sentry" then gun = h.t elseif h.t.kind == "hazard_mine_turret" then mine = h.t end
  end
  check("the gun turns 4.5 degrees a frame and fires 20 frames after it acquires",
    gun and gun.rot_active == 4.5 and gun.activate == 20)
  check("the turret: faster, quicker, and aiming ahead", mine and mine.thinking == 5 and mine.pick_pct == 90 and mine.aim_ahead)
  local shared = require("lib/shared")
  check("the weapons' own turrets as they were", shared.sentry_gun.rot_active == 1.5 and shared.sentry_gun.activate == 60
    and shared.mine_turret.thinking == 15 and not shared.mine_turret.aim_ahead)
end

print("Hazardous Sentries: a neutral Sentry Gun fires at every team, as no team's")
do
  mock()
  local red = M.worm(1, 1, 0, 100, 300)
  install({ sentry_gun = 1, sentry_gun_damage = 7, sentry_gun_push_pct = 40 })
  turn_start(red)
  local a = M.actors[#M.actors]
  local blue = M.worm(2, 2, 1, a.x + 120, a.y - 5)
  blue.vx = 1
  frames(a, 2)
  blue.x = blue.x + 1
  frames(a, 200)
  local shot = M.bullets[1]
  check("it fires", shot ~= nil, #M.bullets)
  check("with its own body as the owner, which keeps out of the round", shot and shot.owner == a and shot.ignore[1] == a)
  check("on the add-on's damage and push", shot and shot.damage == 7 and shot.push_pct == 40)
  blue.x = 5000
  red.x, red.y, red.vx = a.x - 120, a.y - 5, 1
  turn_start(red)
  M.bullets = {}
  frames(a, 300)
  check("and at red too", #M.bullets > 0, #M.bullets)
end

print("Hazardous Sentries: an idle Sentry Gun sleeps, its sweep where an awake one's is")
do
  -- The engine's `a:sleep` (engine/actor_sleep.rs): skipped calls, a living worm within
  -- `near` wakes it, the call that ends it gets `ev.slept`. Each call's head angle, by frame.
  local function run(sleeps)
    mock()
    local red = M.worm(1, 1, 0, 100, 300)
    install({ sentry_gun = 1 })
    turn_start(red)
    local a = M.actors[#M.actors]
    local s = hazards()[1].s
    red.x = -5000
    local asleep, slept, near, angles, calls = 0, 0, nil, {}, 0
    if sleeps then function a:sleep(n, opts) asleep, near = n, opts and opts.near end end
    local blue = M.worm(2, 2, 1, a.x + 2000, a.y - 5)
    blue.vx = 1
    for f = 1, 900 do
      M.frame, M.clock = M.frame + 1, M.clock - 20
      if f > 200 then blue.x = blue.x - 3 end
      local woke = false
      for _, w in ipairs(M.worms) do
        if asleep > 0 and w.hp > 0 and (w.x - a.x) ^ 2 + (w.y - a.y) ^ 2 <= near ^ 2 then woke = true end
      end
      if asleep > 0 and not woke then
        asleep, slept = asleep - 1, slept + 1
      else
        asleep, calls = 0, calls + 1
        local n = slept
        slept = 0
        a.on.frame(a, { slept = n })
        angles[f] = s.angle
      end
      if #M.bullets > 0 then return f, angles, calls end
    end
    return nil, angles, calls
  end
  local awake_at, awake_angles, awake_calls = run(false)
  local at, angles, calls = run(true)
  local same = 0
  for f, angle in pairs(angles) do
    if awake_angles[f] ~= angle then same = nil; break end
    same = same + 1
  end
  check("an awake one fires at the worm walking up", awake_at ~= nil)
  check("one that sleeps fires on the same frame", at == awake_at, tostring(at) .. " vs " .. tostring(awake_at))
  check("each time it wakes, its head is where the awake one's is", same and same == calls, same)
  check("called far less often while no worm was near", calls < awake_calls * 0.6,
    tostring(calls) .. " of " .. tostring(awake_calls))
end

print("Hazardous Sentries: neutral turrets spare each other's arrows; a team's turret doesn't")
do
  mock()
  local red = M.worm(1, 1, 0, 100, 300)
  install({ auto_ballista = 1 })
  turn_start(red)
  local a = M.actors[#M.actors]
  local t
  local before = #M.actors
  a.on.hit(a, { kind = "arrow", team = 0, damage = 10 })
  check("a no-team arrow does nothing", not a.dead and #M.actors == before)
  a.on.hit(a, { kind = "arrow", team = 1, damage = 45 })
  a.on.hit(a, { kind = "arrow", team = 1, damage = 10 })
  check("a team's arrows hurt it", a.dead)
  -- a red team's ballista, placed by a worm
  require("weapons/auto_ballista").setup()
  t = require("lib/shared").auto_ballista
  t.place({ worm = red })
  local mine = M.actors[#M.actors]
  local s = t.state[mine.id]
  mine.on.hit(mine, { kind = "arrow", team = 0, damage = 10 })
  check("a no-team arrow hurts a team's turret", s.health == 40, s.health)
end

print("Hazardous Sentries: a stunned neutral sentry comes back")
do
  mock()
  local red = M.worm(1, 1, 0, 100, 300)
  install({ sentry_laser = 1 })
  turn_start(red)
  local a = M.actors[#M.actors]
  local obj
  for _, o in ipairs(require("lib/electrical").special_targets()) do
    if o.id == a.id then obj = o end
  end
  check("an arc target", obj ~= nil)
  obj.provider.zap(obj, 1)
  local s = obj.s
  check("the Tazer stuns it", s.stun == 2 and s.disabled)
  for _ = 1, 3 do turn_start(red) end
  check("after two turns of anyone's it works again", s.stun == nil and not s.disabled, tostring(s.stun))
  obj.provider.strike(obj, 2)
  check("Lightning makes it the striker's", s.alliance == 2)
end

if failed > 0 then error(failed .. " FAILED") end
print("Hazardous Sentries: ground, box, settings, no team, arrows and stuns: ALL PASS")
