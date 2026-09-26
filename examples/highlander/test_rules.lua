-- Drives mods/examples/highlander/rules.lua against a mocked WA.
--
--   lua mods/examples/highlander/test_rules.lua   (from the repo root)
--
-- The pack is data, not a crate, so this is not part of `cargo test`. Ammo
-- is modelled per alliance row, as WA stores it, and `{ set = n }` is
-- absolute, infinite included, as the engine implements it. Which row a team
-- writes to is the engine's job (`world::ammo_row`), not the pack's, so it is
-- not something this mock can test.

local STOCK = {
  "none", "bazooka", "homing_missile", "mortar", "homing_pigeon",
  "sheep_launcher", "grenade", "cluster_bomb", "banana_bomb", "battle_axe",
  "earthquake", "shotgun", "handgun", "uzi", "minigun", "longbow",
  "fire_punch", "dragon_ball", "kamikaze", "suicide_bomber", "prod",
  "dynamite", "mine", "sheep", "super_sheep", "aqua_sheep", "mole_bomb",
  "air_strike", "napalm_strike", "mail_strike", "mine_strike",
  "mole_squadron", "blow_torch", "pneumatic_drill", "girder",
  "baseball_bat", "girder_pack", "ninja_rope", "bungee", "parachute",
  "teleport", "scales_of_justice", "super_banana", "holy_grenade",
  "flame_thrower", "salvation_army", "mb_bomb", "petrol_bomb", "skunk",
  "ming_vase", "sheep_strike", "carpet_bomb", "mad_cow", "old_woman",
  "donkey", "nuclear_test", "armageddon", "skip_go", "surrender",
  "select_worm", "freeze", "magic_bullet", "jet_pack", "low_gravity",
  "fast_walk", "laser_sight", "invisibility", "damage_x2", "crate_spy",
  "double_turn_time", "crate_shower",
}
local IS_STOCK = {}
for _, n in ipairs(STOCK) do
  IS_STOCK[n] = true
end

-- The scheme's layout: each HL weapon as the stock slot it takes.
local MOVEMENT = {
  girder_pack = 1, ninja_rope = 1, parachute = 1, teleport = 1,
  jet_pack = 1, low_gravity = 1, laser_sight = 1,
}
local SECOND = {
  fire_punch = 1, dragon_ball = 1, kamikaze = 1, prod = 1, girder = 1,
  baseball_bat = 1, shotgun = 1, handgun = 1, uzi = 1, minigun = 1,
  longbow = 1, blow_torch = 1, pneumatic_drill = 1, scales_of_justice = 1,
  armageddon = 1, flame_thrower = 1, nuclear_test = 1, donkey = 1,
  napalm_strike = 1,
}
local SCHEME_OWNED = {
  suicide_bomber = 1, super_sheep = 1, mole_bomb = 1, bungee = 1,
  skip_go = 1, surrender = 1, select_worm = 1, freeze = 1,
  magic_bullet = 1, fast_walk = 1, invisibility = 1, damage_x2 = 1,
  crate_spy = 1, double_turn_time = 1, crate_shower = 1,
}
-- What PX's cavern ranges leave out: the Ferret and the strikes from the
-- sky, and the last three second weapons.
local NOT_IN_CAVES = {
  salvation_army = 1, air_strike = 1, mail_strike = 1, mine_strike = 1,
  mole_squadron = 1, mb_bomb = 1, sheep_strike = 1, carpet_bomb = 1,
  nuclear_test = 1, donkey = 1, napalm_strike = 1,
}

-- ------------------------------------------------------------ mocked WA

local M, ammo, worms, cavern, rng, logs, active, death_seen, replaced

local Worm = {}
Worm.__index = Worm
function Worm:ammo(name, change)
  assert(IS_STOCK[name], "pack asked for a weapon that does not exist: " .. tostring(name))
  local store = ammo[self.alliance]
  if change == nil then
    return store[name] or 0
  end
  assert(type(change) == "table" and change.set, "rules must only ever SET ammo")
  store[name] = change.set
  return change.set
end

local function inventory_api()
  local api = {}

  function api.create(spec)
    local slots, allowed, values = spec.slots, {}, {}
    for _, name in ipairs(slots) do allowed[name] = true end

    local inv = {}
    local function row(worm, create)
      local r = values[worm.id]
      if not r and create then r = {}; values[worm.id] = r end
      return r
    end
    function inv:get(worm, name)
      local r = row(worm)
      return r and (r[name] or 0) or 0
    end
    function inv:set(worm, name, n)
      assert(allowed[name])
      local r = row(worm, true)
      r[name] = n > 0 and n or nil
      return n
    end
    function inv:add(worm, name, n)
      return self:set(worm, name, self:get(worm, name) + (n or 1))
    end
    function inv:remove(worm, name, n)
      return self:set(worm, name, math.max(0, self:get(worm, name) - (n or 1)))
    end
    function inv:list(worm)
      local out, r = {}, row(worm)
      if not r then return out end
      for _, name in ipairs(slots) do
        for _ = 1, r[name] or 0 do out[#out + 1] = name end
      end
      return out
    end
    function inv:deal(worm, pool, count)
      local out = {}
      for _ = 1, count or 1 do
        local name = pool[wa.random(1, #pool)]
        self:add(worm, name, 1)
        out[#out + 1] = name
      end
      return out
    end
    function inv:clear(worm, weapons)
      local r = row(worm)
      if not r then return end
      local names = weapons
      if names == nil or names == "all" then names = slots end
      if type(names) == "string" then names = { names } end
      for _, name in ipairs(names) do r[name] = nil end
    end
    function inv:transfer(from, to, opts)
      opts = opts or {}
      local names = opts.weapons
      if names == nil or names == "all" then names = slots end
      if type(names) == "string" then names = { names } end
      local moved = {}
      for _, name in ipairs(names) do
        local have = self:get(from, name)
        local n = opts.amount and math.min(have, opts.amount) or have
        if n > 0 then
          self:add(to, name, n)
          if (opts.mode or "move") == "move" then self:remove(from, name, n) end
          moved[name] = n
        end
      end
      return moved
    end
    function inv:apply(worm, opts)
      opts = opts or {}
      if opts.clear then
        local seen = {}
        for _, live in ipairs(wa.worms.all()) do
          if not seen[live.alliance] then
            seen[live.alliance] = true
            for _, name in ipairs(slots) do live:ammo(name, { set = 0 }) end
          end
        end
      end
      local names = opts.weapons or slots
      local r = row(worm)
      if not r then return end
      for _, name in ipairs(names) do
        if (r[name] or 0) > 0 then
          worm:ammo(name, { set = opts.each or r[name] })
        end
      end
    end
    return inv
  end
  return api
end

local function new_match(opts)
  opts = opts or {}
  M, logs, active, death_seen, replaced = {}, {}, nil, {}, {}
  cavern = opts.cavern or false
  rng = 12345
  ammo = {}
  worms = {}
  -- Two teams of two, each its own alliance: team 1 is alliance 0, team 2 is 1.
  for team = 1, 2 do
    ammo[team - 1] = {}
    for index = 0, 1 do
      worms[#worms + 1] = setmetatable({
        id = team * 16 + index, team = team, alliance = team - 1, hp = 100,
      }, Worm)
    end
  end
  -- A stock-like scheme: infinite bazooka, a few counted weapons, and two
  -- slots Highlander leaves alone (Teleport's and Skip Go's).
  for a = 0, 1 do
    ammo[a].bazooka = -1
    ammo[a].grenade = 5
    ammo[a].invisibility = 2
    ammo[a].skip_go = -1
  end
  wa = {
    log = function(s) logs[#logs + 1] = s end,
    hud = { line = function() end },
    msg = { FRAME_FINISH = 2, START_TURN = 0x34, FIRE_WEAPON = 0x26 },
    world = { cavern = function() return cavern end },
    -- A fixed LCG: the pack must not care which numbers, only that it draws
    -- through here.
    random = function(lo, hi)
      rng = (rng * 1103515245 + 12345) % 2147483648
      return lo + rng % (hi - lo + 1)
    end,
    worms = {
      all = function()
        local live = {}
        -- Deliberately NOT in id order: the pack must sort for itself.
        for i = #worms, 1, -1 do
          live[#live + 1] = worms[i]
        end
        return live
      end,
    },
    inventory = inventory_api(),
    land = {
      cut = function(spec)
        M.cuts = M.cuts or {}
        M.cuts[#M.cuts + 1] = spec
      end,
      trace = function() return M.trace_hit end,
    },
    draw = {
      quad = function(q) M.quads[#M.quads + 1] = q end,
      random = function() return 0.5 end,
    },
    sound = {
      play = function(target, name) M.sounds[#M.sounds + 1] = name end,
    },
    actors = {
      spawn = function(spec)
        local a = { sprite = spec.sprite, x = spec.x, y = spec.y, dead = false }
        function a:gfx(g) self.angle, self.scale = g.angle, g.scale end
        function a:frame(i) self.shown = i end
        function a:despawn() self.dead = true end
        M.spawned = M.spawned or {}
        M.spawned[#M.spawned + 1] = a
        return a
      end,
    },
    weapons = {
      replace = function(spec)
        assert(IS_STOCK[spec.weapon], "replace of a slot that does not exist: " .. tostring(spec.weapon))
        replaced[#replaced + 1] = spec
      end,
    },
    on = {
      -- Every handler, in registration order, as the engine keeps them.
      worm_message = function(f)
        M.handlers = M.handlers or {}
        M.handlers[#M.handlers + 1] = f
        M.message = function(w, msg)
          for _, h in ipairs(M.handlers) do h(w, msg) end
        end
      end,
      turn_start = function(f) M.turn_start = f end,
      missile_frame = function(f) M.missile = f end,
      death = function(f) M.death = f end,
      hud = function(f) M.hud = f end,
      draw = function(f) M.draw = f end,
    },
  }
  M.quads, M.sounds, M.trace_hit = {}, {}, nil
  dofile("mods/examples/highlander/rules.lua")
end

local function worm(id)
  for _, w in ipairs(worms) do
    if w.id == id then
      return w
    end
  end
end

local function frame()
  for _, w in ipairs(worms) do
    M.message(w, 2)
    if w.hp <= 0 and not death_seen[w.id] then
      death_seen[w.id] = true
      M.death({ victim = w, active = active })
    end
  end
end

local function turn(id)
  active = worm(id)
  M.message(active, 0x34)
  M.turn_start({ worm = active, active = active })
end

local function kill(id)
  worm(id).hp = 0
  frame()
end

local function remove(id)
  for i, w in ipairs(worms) do
    if w.id == id then
      table.remove(worms, i)
      return
    end
  end
end

-- What the pack dealt, read back out of its own log lines.
local function hand(id)
  for _, line in ipairs(logs) do
    local who, list = line:match("^highlander: worm (%d+) dealt (.-) %(")
    if tonumber(who) == id then
      local out = {}
      for name in list:gmatch("[^, ]+") do
        out[#out + 1] = name
      end
      return out
    end
  end
end

local fails = 0
local function check(name, cond, detail)
  print(("  %s %s%s"):format(cond and "ok  " or "FAIL", name, detail and ("   [" .. detail .. "]") or ""))
  if not cond then
    fails = fails + 1
  end
end

local function usable(alliance)
  local out = {}
  for name, n in pairs(ammo[alliance]) do
    if n ~= 0 and not SCHEME_OWNED[name] then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local function sorted(list)
  local c = {}
  for i, v in ipairs(list) do
    c[i] = v
  end
  table.sort(c)
  return c
end

local function same(a, b)
  return table.concat(sorted(a), ",") == table.concat(sorted(b), ",")
end

-- ------------------------------------------------------------ tests

print("weapons: the ported slots take the scheme's records")
do
  new_match()
  local by_slot, dupes = {}, false
  for _, spec in ipairs(replaced) do
    if by_slot[spec.weapon] then dupes = true end
    by_slot[spec.weapon] = spec
  end
  check("38 slots replaced, each once", #replaced == 38 and not dupes, tostring(#replaced))
  local own_file = true
  for slot, spec in pairs(by_slot) do
    if spec.wep ~= "weps/" .. slot .. ".wep" or spec.copy_from then own_file = false end
  end
  check("each from its own scheme record", own_file)
  check("Baseball Bat on the girder slot, with its own icon",
    by_slot.girder and by_slot.girder.panel_icon == "baseball_bat")
  check("a weapon on its own slot keeps its icon",
    by_slot.dynamite and by_slot.dynamite.panel_icon == nil)
  check("Windy Cluster brings PX's icon and bits",
    by_slot.cluster_bomb and by_slot.cluster_bomb.panel_icon == "sprites/windy_cluster/ico_windyc.png"
      and by_slot.cluster_bomb.cluster.sprite == "sprites/windy_cluster/cluster")
end

print("pools: every stock slot is in exactly one place")
do
  new_match()
  turn(16)
  -- Every slot the pack zeroed is a pooled slot; every other slot it never touched.
  local pooled = {}
  for _, alliance in ipairs({ 0, 1 }) do
    for name in pairs(ammo[alliance]) do
      if not SCHEME_OWNED[name] then
        pooled[name] = true
      end
    end
  end
  local n, bad = 0, {}
  for name in pairs(pooled) do
    n = n + 1
    if not IS_STOCK[name] then
      bad[#bad + 1] = name
    end
  end
  check("55 pooled slots", n == 55, tostring(n))
  check("all pooled names are stock", #bad == 0, table.concat(bad, ","))
  local untouched = true
  for name in pairs(SCHEME_OWNED) do
    if pooled[name] then
      untouched = false
    end
  end
  check("scheme-owned slots are never pooled", untouched)
  check("Teleport's slot left to the scheme", ammo[0].invisibility == 2 and ammo[1].invisibility == 2)
  check("skip go left to the scheme", ammo[0].skip_go == -1)
end

print("deal: one from each pool, per worm")
do
  new_match()
  frame()
  local ok = true
  for _, id in ipairs({ 16, 17, 32, 33 }) do
    local h = hand(id)
    if not h or #h ~= 3 or SECOND[h[1]] or MOVEMENT[h[1]] or SCHEME_OWNED[h[1]]
        or not SECOND[h[2]] or not MOVEMENT[h[3]] then
      ok = false
    end
  end
  check("every worm gets offensive, second, movement", ok)
end

print("deal: deterministic, each worm dealt on its own first message")
do
  new_match()
  frame()
  local first = { hand(16), hand(17), hand(32), hand(33) }
  new_match()
  frame()
  local again = { hand(16), hand(17), hand(32), hand(33) }
  local same_hands = true
  for i = 1, 4 do
    if table.concat(first[i], ",") ~= table.concat(again[i], ",") then
      same_hands = false
    end
  end
  check("same RNG, same hands", same_hands)
  local order = {}
  for _, line in ipairs(logs) do
    local who = line:match("^highlander: worm (%d+) dealt")
    if who then
      order[#order + 1] = who
    end
  end
  check("dealt in message order", table.concat(order, ",") == "16,17,32,33", table.concat(order, ","))
end

print("deal: a worm that first speaks late still gets a hand")
do
  new_match()
  -- Only worm 16 exists when the first message arrives.
  local later = {}
  for i = #worms, 2, -1 do
    table.insert(later, 1, table.remove(worms, i))
  end
  frame()
  for _, w in ipairs(later) do
    worms[#worms + 1] = w
  end
  frame()
  local ok = true
  for _, id in ipairs({ 16, 17, 32, 33 }) do
    if not hand(id) or #hand(id) ~= 3 then
      ok = false
    end
  end
  check("all four dealt", ok)
end

print("cavern: PX's short ranges, no strikes or Ferret")
do
  local banned = false
  for seed = 1, 40 do
    new_match({ cavern = true })
    rng = seed * 7919
    frame()
    for _, id in ipairs({ 16, 17, 32, 33 }) do
      local h = hand(id)
      if NOT_IN_CAVES[h[1]] or NOT_IN_CAVES[h[2]] then
        banned = true
      end
    end
  end
  check("160 cavern hands, none of them", not banned)
  local seen = false
  for seed = 1, 40 do
    new_match()
    rng = seed * 7919
    frame()
    for _, id in ipairs({ 16, 17, 32, 33 }) do
      local h = hand(id)
      if NOT_IN_CAVES[h[1]] or NOT_IN_CAVES[h[2]] then
        seen = true
      end
    end
  end
  check("...while open maps do deal them", seen)
end

print("turn: only the active worm's hand is usable, one of each")
do
  new_match()
  frame()
  turn(16)
  check("team 1 holds exactly worm 16's hand", same(usable(0), hand(16)),
    table.concat(usable(0), ","))
  local ones = true
  for _, name in ipairs(hand(16)) do
    if ammo[0][name] ~= 1 then
      ones = false
    end
  end
  check("each at exactly 1", ones)
  check("the other team holds nothing", #usable(1) == 0, table.concat(usable(1), ","))
  check("the scheme's infinite bazooka is gone unless dealt",
    ammo[1].bazooka == 0)
end

print("turn: the previous worm's hand is taken back")
do
  new_match()
  frame()
  turn(16)
  turn(32)
  check("team 1 holds nothing", #usable(0) == 0, table.concat(usable(0), ","))
  check("team 2 holds worm 32's hand", same(usable(1), hand(32)))
end

print("turn: a teammate's hand is not usable on your turn")
do
  new_match()
  frame()
  turn(17)
  check("team 1 holds worm 17's hand, not 16's", same(usable(0), hand(17)))
end

print("death: the active worm takes the dead worm's hand, at once")
do
  new_match()
  frame()
  turn(16)
  local victim = hand(32)
  kill(32)
  local expect = {}
  for _, n in ipairs(hand(16)) do expect[#expect + 1] = n end
  for _, n in ipairs(victim) do expect[#expect + 1] = n end
  -- Duplicates collapse in ammo (both are just "1"), so compare as sets.
  local want = {}
  for _, n in ipairs(expect) do want[n] = true end
  local got = {}
  for _, n in ipairs(usable(0)) do got[n] = true end
  local ok = true
  for n in pairs(want) do if not got[n] then ok = false end end
  for n in pairs(got) do if not want[n] then ok = false end end
  check("stolen weapons usable this turn", ok, table.concat(usable(0), ","))
  -- The dead worm's entity goes away; its id must be all the pack needs.
  remove(32)
  turn(33)
  turn(16)
  local ok2 = true
  for n in pairs(want) do if ammo[0][n] ~= 1 then ok2 = false end end
  check("and kept on the stealer's next turn", ok2)
end

print("death: a friendly kill still transfers, as in PX")
do
  new_match()
  frame()
  turn(16)
  kill(17)
  local has = {}
  for _, n in ipairs(usable(0)) do has[n] = true end
  local ok = true
  for _, n in ipairs(hand(17)) do if not has[n] then ok = false end end
  check("teammate's hand goes to the active worm", ok)
end

print("death: one death, one transfer")
do
  new_match()
  frame()
  turn(16)
  kill(32)
  local n = 0
  for _, line in ipairs(logs) do
    if line:find("took") then n = n + 1 end
  end
  frame()
  frame()
  local m = 0
  for _, line in ipairs(logs) do
    if line:find("took") then m = m + 1 end
  end
  check("no second transfer on later frames", n == 1 and m == 1, n .. " then " .. m)
end

print("death: the active worm dying on its own turn loses its hand, gives nothing")
do
  new_match()
  frame()
  turn(16)
  kill(16)
  check("team 1 holds nothing", #usable(0) == 0, table.concat(usable(0), ","))
  local took = false
  for _, line in ipairs(logs) do
    if line:find("took") then took = true end
  end
  check("no transfer", not took)
end

print("death: a worm that dies after its stealer died gives nothing")
do
  new_match()
  frame()
  turn(16)
  kill(16)
  kill(32)
  local took = false
  for _, line in ipairs(logs) do
    if line:find("took") then took = true end
  end
  check("no transfer to a dead worm", not took)
end

print("inventory verbs: damage and weapon conditions choose arbitrary targets")
do
  new_match()
  local loot = wa.inventory.create({
    id = "conditional-test", slots = { "bazooka", "grenade" },
  })
  loot:set(worm(32), "bazooka", 2)
  loot:set(worm(32), "grenade", 1)
  local hit = {
    victim = worm(32), attacker = worm(16),
    lost = 25, weapon = "baseball_bat",
  }
  if hit.lost >= 20 and hit.weapon == "baseball_bat" then
    loot:transfer(hit.victim, hit.attacker, {
      weapons = "bazooka", amount = 1, mode = "move",
    })
  end
  check("conditioned steal moved one selected weapon",
    loot:get(worm(16), "bazooka") == 1
      and loot:get(worm(32), "bazooka") == 1
      and loot:get(worm(32), "grenade") == 1)
end

print("fire jump: PX's timeline after a fire punch")
do
  new_match()
  frame()
  local w = worm(16)
  w.weapon, w.facing, w.vx, w.vy = "fire_punch", -1, 0, 0
  ammo[w.alliance].fire_punch = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  -- WA's wind-up: the worm stands still, and nothing may move it.
  for _ = 1, 12 do M.message(w, wa.msg.FRAME_FINISH) end
  check("nothing during the wind-up", w.vx == 0 and w.vy == 0, w.vx .. " " .. w.vy)
  -- FireFinal: WA's setup_Punching starts the worm up at 6.
  local PX = 0x10000
  w.vy = -6 * PX
  local at = {}
  for t = 1, 215 do
    if t == 100 then w.vy = 8 * PX end -- falling fast mid-glide
    M.message(w, wa.msg.FRAME_FINISH)
    at[t] = { vx = w.vx, vy = w.vy }
  end
  check("up at 9 on the punch's first frame", at[1].vy == -9 * PX, tostring(at[1].vy))
  check("forward, the way it faces, 30 frames in", at[30].vx == -4 * PX and at[29].vx == 0,
    tostring(at[30].vx))
  check("a little higher at 60", at[60].vy == -10 * PX, tostring(at[60].vy))
  check("a fall past 5 goes back to 4", at[100].vy == 4 * PX, tostring(at[100].vy))
  w.vy = 8 * PX
  M.message(w, wa.msg.FRAME_FINISH)
  check("and lets go after 210 frames", w.vy == 8 * PX, tostring(w.vy))
  check("no cut of its own: WA's punch cuts", not M.cuts)
  local other = worm(32)
  other.weapon, other.vy = "bazooka", 0
  M.message(other, wa.msg.FIRE_WEAPON)
  other.vy = -6 * PX
  M.message(other, wa.msg.FRAME_FINISH)
  check("another weapon does not jump", other.vy == -6 * PX)
end

print("fire jump: a wind-up that never ends in a punch")
do
  new_match()
  frame()
  local w = worm(16)
  w.weapon, w.vy = "fire_punch", 0
  ammo[w.alliance].fire_punch = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  for _ = 1, 100 do M.message(w, wa.msg.FRAME_FINISH) end
  w.vy = -3 * 0x10000 -- a later jump of some other kind
  M.message(w, wa.msg.FRAME_FINISH)
  check("is forgotten", w.vy == -3 * 0x10000, tostring(w.vy))
end

print("px holds: the sprite builder at run time")
do
  new_match()
  frame()
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming = "grenade", 1, 100 * 0x10000, 50 * 0x10000, true
  M.message(w, wa.msg.FRAME_FINISH)
  check("dormant without worm.aim", not M.spawned)
  w.aim = 0.5
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local weapon, hand = M.spawned[1], M.spawned[2]
  check("a weapon and a hand while aiming", weapon and hand and weapon.sprite == "sprites/px_hold/sticky_bomb"
    and hand.sprite == "sprites/px_hold/hand_rad_lower")
  check("grown in to full size after 20 frames", weapon.scale == 1 and math.abs(hand.scale - 0.8) < 1e-9,
    tostring(weapon.scale))
  local right = weapon.x - w.x
  w.facing = -1
  M.message(w, wa.msg.FRAME_FINISH)
  check("positions are 16.16 integers", math.type(weapon.x) == "integer" and math.type(hand.y) == "integer")
  check("facing left mirrors the weapon", math.abs((weapon.x - w.x) + right) <= 1 and weapon.facing == -1,
    right .. " " .. (weapon.x - w.x))
  w.aiming = false
  M.message(w, wa.msg.FRAME_FINISH)
  check("and it goes when the worm stops aiming", weapon.dead and hand.dead)
  w.aiming, w.weapon = true, "bazooka"
  local before = #M.spawned
  M.message(w, wa.msg.FRAME_FINISH)
  check("no hold for a weapon without one", #M.spawned == before)
end

print("px holds: a weapon drawn with no hand, animated")
do
  new_match()
  frame()
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim = "longbow", 1, 100 * 0x10000, 50 * 0x10000, true, 0.5
  M.message(w, wa.msg.FRAME_FINISH)
  local bolt = M.spawned[#M.spawned]
  check("only the weapon: PX draws no hand", #M.spawned == 1 and bolt.sprite == "sprites/px_hold/shadow_bolt")
  local shown = {}
  for _ = 1, 26 do
    M.message(w, wa.msg.FRAME_FINISH)
    shown[bolt.shown] = true
  end
  check("the bolt animates in the hand", shown[0] and shown[5])
  w.aiming = false
  M.message(w, wa.msg.FRAME_FINISH)
  check("and goes when the worm stops aiming", bolt.dead)
end

print("sniper rifle: PX's laser sight, drawn only")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  for _, o in ipairs(worms) do
    o.x, o.y = -5000 * P, 0 -- behind the ray
  end
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim, w.turn = "handgun", 1, 100 * P, 50 * P, true, 0.5, true
  M.message(w, wa.msg.FRAME_FINISH) -- the rifle is drawn with this aim
  w.aim = 0.53 -- WA's crosshair, rewritten at render time: the ray keeps the rifle's
  M.draw()
  check("a full-length ray: 150 quads and the tip", #M.quads == 151, tostring(#M.quads))
  local q = M.quads[1]
  -- The quad's first corner is the start plus half the ray's width, across.
  local sx, sy = (q.points[1][1] + q.points[4][1]) / 2, (q.points[1][2] + q.points[4][2]) / 2
  check("from 12 pixels out along the aim, on the barrel 2 above the centre line",
    math.abs(sx - 112 * P) < P / 8 and math.abs(sy - 48 * P) < P / 8, sx / P .. "," .. sy / P)
  check("added, red, brighter at the start", q.blend == "add" and q.colors[1] == 0xC0FF6060
    and q.colors[2] == 0xFFFF3030)
  local tip = M.quads[#M.quads]
  check("fading out at the tip", tip.colors[2] == 0x10FF3030 and tip.colors[1] == 0xFFFF3030)
  M.quads, M.trace_hit = {}, { x = 312 * P, y = 50 * P }
  M.draw()
  check("stops at terrain 200 pixels on", #M.quads == 3, tostring(#M.quads))
  M.quads, M.trace_hit = {}, nil
  local other = worm(32)
  other.x, other.y = 172 * P, 52 * P
  M.draw()
  check("and at a worm in the way", #M.quads == 2, tostring(#M.quads))
  M.quads = {}
  w.turn = false
  M.draw()
  w.turn, w.aiming = true, false
  M.message(w, wa.msg.FRAME_FINISH)
  M.draw()
  check("only the current worm, only while aiming", #M.quads == 0)
  w.aiming, w.facing, w.x, w.aim = true, -1, 300 * P, 0.5
  M.message(w, wa.msg.FRAME_FINISH)
  M.draw()
  q = M.quads[1]
  sx, sy = (q.points[1][1] + q.points[4][1]) / 2, (q.points[1][2] + q.points[4][2]) / 2
  check("facing left: 12 out to the left, the barrel still above",
    math.abs(sx - 288 * P) < P / 8 and math.abs(sy - 48 * P) < P / 8, sx / P .. "," .. sy / P)
  M.quads = {}
  w.aiming = false
  M.message(w, wa.msg.FRAME_FINISH)
  ammo[w.alliance].handgun = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  check("its own shot sound on firing", M.sounds[1] == "sounds/sniper_firing.wav")
end

print("px missile sprites: WeapSprite at run time")
do
  new_match()
  frame()
  local PX = 0x10000
  local m = { id = 77, phase = "post", weapon = "longbow", x = 10 * PX, y = 20 * PX, vx = 3 * PX, vy = 0 }
  M.missile(m)
  local bolt = M.spawned and M.spawned[#M.spawned]
  check("a bolt on the Shadow-Bolt's missile", bolt and bolt.sprite == "sprites/shadow_bolt/bolt"
    and bolt.x == m.x and bolt.y == m.y)
  check("flying right, turned to its flight", bolt.facing == 1 and math.abs(bolt.angle - 90) < 1e-6,
    tostring(bolt.angle))
  local before = #M.spawned
  m.vx = -3 * PX
  M.missile(m)
  check("one bolt per missile, mirrored flying left", #M.spawned == before and bolt.facing == -1)
  local shown = {}
  for _ = 1, 26 do
    M.missile(m)
    shown[bolt.shown] = true
  end
  check("steps through all six frames", shown[0] and shown[5], tostring(bolt.shown))
  m.phase = "pre"
  M.missile(m)
  m.phase, m.weapon, m.id = "post", "bazooka", 78
  M.missile(m)
  check("nothing for another weapon's missile", #M.spawned == before)
end

print("")
if fails == 0 then
  print("ALL PASS")
else
  print(("%d FAILED"):format(fails))
  os.exit(1)
end
