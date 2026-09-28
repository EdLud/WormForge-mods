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
local unregistered_sounds = {} -- pack WAVs played but never registered

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
        gravity = 0x10000, -- WA's normal
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
    hud = { line = function(text) M.hud_lines = M.hud_lines or {}; M.hud_lines[#M.hud_lines + 1] = text end },
    msg = { FRAME_FINISH = 2, START_TURN = 0x34, FIRE_WEAPON = 0x26, JUMP = 0x24 },
    world = {
      cavern = function() return cavern end,
      retreat = function() return M.retreat or 0 end,
      water = function() return M.water or 0x7FFFFFFF end,
      gravity = function() return M.gravity or 0 end,
      wind = function() return M.wind or 0 end,
      keys = function() return { sprint = M.shift or false, digit = M.digit } end,
      set_gravity = function(v) M.gravity = v end,
      set_wind = function(v) M.wind = v end,
    },
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
      dig = function(spec)
        M.digs = M.digs or {}
        M.digs[#M.digs + 1] = spec
      end,
      trace = function() return M.trace_hit end,
    },
    draw = {
      quad = function(q) M.quads[#M.quads + 1] = q end,
      random = function() return 0.5 end,
    },
    sound = {
      play = function(target, name)
        M.sounds[#M.sounds + 1] = name
        -- A pack WAV plays only once an entry registers it (`sounds`);
        -- otherwise the engine plays nothing, without a word.
        if type(name) == "string" then
          local registered = false
          for _, r in ipairs(replaced) do
            for _, snd in ipairs(r.sounds or {}) do
              if snd == name then registered = true end
            end
          end
          if not registered then unregistered_sounds[name] = true end
        end
      end,
    },
    actors = {
      spawn = function(spec)
        -- As the engine: outside a fire, click or actor callback, a spawn
        -- needs its owner named.
        if spec.owner == nil then
          error("spawn needs an owner worm or actor", 2)
        end
        local a = { sprite = spec.sprite, x = spec.x, y = spec.y, dead = false, explode = spec.explode,
                    owner = spec.owner }
        function a:gfx(g)
          self.angle, self.scale, self.tint, self.blend, self.depth = g.angle, g.scale, g.tint, g.blend, g.depth
        end
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
      -- As the engine: a real missile, its id.
      launch = function(spec)
        assert(IS_STOCK[spec.weapon], "launch from a slot that does not exist: " .. tostring(spec.weapon))
        assert(spec.owner ~= nil, "launch needs an owner")
        M.launched = M.launched or {}
        M.launched[#M.launched + 1] = spec
        return 9000 + #M.launched
      end,
    },
    on = {
      -- Every handler, in registration order, as the engine keeps them.
      worm_message = function(f)
        M.handlers = M.handlers or {}
        M.handlers[#M.handlers + 1] = f
        -- "eat" from any handler swallows the message, as the engine's.
        M.message = function(w, msg)
          local eat
          for _, h in ipairs(M.handlers) do
            if h(w, msg) == "eat" then eat = "eat" end
          end
          return eat
        end
      end,
      -- Every handler, as for worm_message: the balloon's and the rules'.
      turn_start = function(f)
        M.turn_starts = M.turn_starts or {}
        M.turn_starts[#M.turn_starts + 1] = f
        M.turn_start = function(...)
          for _, h in ipairs(M.turn_starts) do h(...) end
        end
      end,
      missile_frame = function(f)
        M.missile_handlers = M.missile_handlers or {}
        M.missile_handlers[#M.missile_handlers + 1] = f
        M.missile = function(m)
          for _, h in ipairs(M.missile_handlers) do h(m) end
        end
      end,
      death = function(f) M.death = f end,
      hud = function(f) M.hud = f end,
      draw = function(f)
        M.draws = M.draws or {}
        M.draws[#M.draws + 1] = f
        M.draw = function()
          for _, h in ipairs(M.draws) do h() end
        end
      end,
      contact = function(f)
        M.contacts = M.contacts or {}
        M.contacts[#M.contacts + 1] = f
        M.contact = function(...)
          for _, h in ipairs(M.contacts) do h(...) end
        end
      end,
    },
  }
  M.quads, M.sounds, M.trace_hit, M.draws = {}, {}, nil, nil
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
  check("49 slots replaced, each once", #replaced == 49 and not dupes, tostring(#replaced))
  -- The loader skips a replace the manifest does not declare, silently.
  -- (Checked where the suite can read the pack's files: run from the repo,
  -- not inside the engine's loader test.)
  local toml = io and io.open("mods/examples/highlander/mod.toml")
  if toml then
    local manifest = toml:read("a")
    toml:close()
    local declared = {}
    for name in manifest:match("replace = %[(.-)%]"):gmatch('"([%w_]+)"') do
      declared[name] = true
    end
    local undeclared = {}
    for _, r in ipairs(replaced) do
      if not declared[r.weapon] then undeclared[#undeclared + 1] = r.weapon end
    end
    check("every replaced slot is declared in mod.toml", #undeclared == 0, table.concat(undeclared, ","))
  end
  local own_file = true
  for slot, spec in pairs(by_slot) do
    if spec.copy_from ~= slot or spec.wep then own_file = false end
  end
  check("each from stock via copy_from (no .wep file)", own_file)
  check("Baseball Bat on the girder slot, with its own icon",
    by_slot.girder and by_slot.girder.panel_icon == "baseball_bat")
  check("a weapon on its own slot keeps its icon",
    by_slot.dynamite and by_slot.dynamite.panel_icon == nil)
  check("Priceless Ming Vase: the stock vase, as the scheme tunes it",
    by_slot.ming_vase and by_slot.ming_vase.panel_icon == nil and by_slot.ming_vase.on_fire == nil)
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

print("turn: three Hot Air Balloons, as PX's GiveWeapons")
do
  new_match()
  frame()
  ammo[0].bungee = 1 -- one left over from the last turn
  turn(16)
  check("the active team has 3 again", ammo[0].bungee == 3, tostring(ammo[0].bungee))
  check("and a Wind Changer", ammo[0].surrender == 1, tostring(ammo[0].surrender))
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

print("px holds: every hold places, PX's defaults filling the rest")
do
  local P = 0x10000
  for _, slot in ipairs({ "grenade", "super_banana", "homing_missile", "mine", "handgun", "longbow" }) do
    new_match()
    frame()
    local w = worm(16)
    w.weapon, w.facing, w.x, w.y, w.aiming, w.aim = slot, 1, 100 * P, 50 * P, true, 0.5
    local ok, err = pcall(function()
      for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
    end)
    local front = M.spawned and #M.spawned > 0
    for _, a in ipairs(M.spawned or {}) do
      front = front and a.depth ~= nil and a.depth <= 0x10000
    end
    check(slot .. " aims without an error, in front of the worm", ok and front, tostring(err))
  end
  -- The Chilli Bomb sets no radial rotations: CWormAnimParams' 1.0, half a
  -- turn, cocks it back behind the head, the hand further back.
  new_match()
  frame()
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim = "super_banana", 1, 100 * P, 50 * P, true, 0.5
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local chilli, hand = M.spawned[1], M.spawned[2]
  check("the Chilli held back, 9 pixels behind; the hand 13",
    math.abs(chilli.x - (w.x - 9 * P)) <= 1 and math.abs(hand.x - (w.x - 13 * P)) <= 1,
    ((chilli.x - w.x) / P) .. " " .. ((hand.x - w.x) / P))
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

print("px holds: put away, the grow-in played backwards")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim, w.turn, w.state =
    "handgun", 1, 100 * P, 50 * P, true, 0.5, true, "standing"
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local rifle = M.spawned[#M.spawned]
  check("the rifle, grown in", rifle.sprite == "sprites/px_hold/sniper_rifle" and rifle.scale == 1)
  -- The last shot: WA's firing states have no name, and then the worm
  -- stands with the next weapon already selected, putting the rifle away.
  ammo[w.alliance].handgun = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  w.aiming, w.state = false, nil
  M.message(w, wa.msg.FRAME_FINISH)
  check("up while it fires", not rifle.dead and rifle.scale == 1)
  w.weapon, w.state = "bazooka", "standing"
  M.message(w, wa.msg.FRAME_FINISH)
  local back = M.spawned[#M.spawned]
  check("back at full size as WA puts it away", back ~= rifle and not back.dead
    and back.sprite == "sprites/px_hold/sniper_rifle" and back.scale == 1)
  M.quads = {}
  M.draw()
  check("with no laser", #M.quads == 0, tostring(#M.quads))
  local scales = {}
  for _ = 1, 20 do
    M.message(w, wa.msg.FRAME_FINISH)
    scales[#scales + 1] = back.scale
  end
  check("shrinking along the grow-in backwards", scales[1] == 0.95 and scales[2] == 0.9
    and scales[20] == 0, table.concat(scales, " "))
  check("over WA's 20 frames", not back.dead)
  M.message(w, wa.msg.FRAME_FINISH)
  check("then gone", back.dead)

  -- Standing with the same weapon is no put-away: PX's instant drop.
  w.weapon, w.aiming = "handgun", true
  for _ = 1, 5 do M.message(w, wa.msg.FRAME_FINISH) end
  local before = #M.spawned
  w.aiming = false
  M.message(w, wa.msg.FRAME_FINISH)
  M.message(w, wa.msg.FRAME_FINISH)
  check("the same weapon, standing: gone at once", #M.spawned == before and M.spawned[before].dead)
end

print("px holds: a weapon drawn out again grows in again")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim, w.turn, w.state =
    "handgun", 1, 100 * P, 50 * P, true, 0.5, true, nil
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local first = M.spawned[#M.spawned]
  check("the rifle, grown in", first.scale == 1)
  -- Another weapon aimed (no named state), then the rifle again: no shot.
  w.weapon = "bazooka"
  for _ = 1, 5 do M.message(w, wa.msg.FRAME_FINISH) end
  w.weapon = "handgun"
  M.message(w, wa.msg.FRAME_FINISH)
  local again = M.spawned[#M.spawned]
  check("drawn out again: a new rifle, growing in from nothing", again ~= first and first.dead
    and again.scale == 0, tostring(again.scale))
  -- And no stray put-away later for the rifle aimed before.
  w.aiming, w.weapon, w.state = false, "bazooka", "standing"
  local before = #M.spawned
  M.message(w, wa.msg.FRAME_FINISH)
  M.message(w, wa.msg.FRAME_FINISH)
  check("the put-away of the rifle just aimed, and only that (the rifle and its flash)", #M.spawned == before + 2)
end

print("px holds: a thrown Sticky Bomb is not put away")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim, w.turn, w.state =
    "grenade", 1, 100 * P, 50 * P, true, 0.5, true, nil
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local bomb = M.spawned[#M.spawned - 1]
  check("the Sticky Bomb in hand", bomb.sprite == "sprites/px_hold/sticky_bomb" and bomb.scale == 1)
  -- Thrown, then the worm stands with the next weapon selected.
  ammo[w.alliance].grenade = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  w.state = "prefiring"
  M.message(w, wa.msg.FRAME_FINISH)
  w.aiming, w.state = false, nil
  M.message(w, wa.msg.FRAME_FINISH)
  check("gone as it is thrown", bomb.dead)
  local before = #M.spawned
  w.weapon, w.state = "bazooka", "standing"
  for _ = 1, 3 do M.message(w, wa.msg.FRAME_FINISH) end
  check("nothing put away after the throw", #M.spawned == before)

  -- Not thrown: switched away while aiming it, it is put away.
  w.weapon, w.aiming, w.state = "grenade", true, nil
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  w.aiming = false
  M.message(w, wa.msg.FRAME_FINISH)
  before = #M.spawned
  w.weapon, w.state = "bazooka", "standing"
  M.message(w, wa.msg.FRAME_FINISH)
  local away = M.spawned[#M.spawned - 1]
  check("put away when switched away unthrown", #M.spawned == before + 2
    and away.sprite == "sprites/px_hold/sticky_bomb")
end

print("px holds: the Igniter stays up through its shot")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim, w.turn, w.state =
    "homing_missile", 1, 100 * P, 50 * P, true, 0.5, true, "standing"
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local igniter = M.spawned[#M.spawned - 1]
  check("the Igniter, grown in", igniter.sprite == "sprites/px_hold/igniter" and igniter.scale == 1)
  local before = #M.spawned
  ammo[w.alliance].homing_missile = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  -- As WA does it: the wind-up still aims (0x68, unnamed; then prefiring),
  -- then the firing states neither aim nor have a name.
  w.state = nil
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "prefiring"
  M.message(w, wa.msg.FRAME_FINISH)
  w.aiming, w.state = false, nil
  for _ = 1, 4 do M.message(w, wa.msg.FRAME_FINISH) end
  check("up through the wind-up and WA's firing states, at full size", not igniter.dead
    and igniter.scale == 1 and #M.spawned == before)
  -- Aiming again ends the shot; walking off after that is no shot: gone, as
  -- in PX.
  w.aiming = true
  M.message(w, wa.msg.FRAME_FINISH)
  w.aiming = false
  M.message(w, wa.msg.FRAME_FINISH)
  check("but not while walking off", igniter.dead)

  -- The Shadow-Bolt's crossbow too.
  w.weapon, w.aiming, w.state = "longbow", true, nil
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local crossbow = M.spawned[#M.spawned]
  check("the Shadow-Bolt's crossbow", crossbow.sprite == "sprites/px_hold/shadow_bolt")
  ammo[w.alliance].longbow = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  w.state = "prefiring"
  M.message(w, wa.msg.FRAME_FINISH)
  w.aiming, w.state = false, nil
  for _ = 1, 4 do M.message(w, wa.msg.FRAME_FINISH) end
  check("up through its shot", not crossbow.dead and crossbow.scale == 1)
  w.aiming = true
  M.message(w, wa.msg.FRAME_FINISH)

  -- The Sniper Rifle too, with its laser, through each of its three shots.
  for _, o in ipairs(worms) do
    if o ~= w then
      o.x, o.y = -5000 * P, 0 -- out of the laser's way
    end
  end
  w.weapon, w.aiming = "handgun", true
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local rifle = M.spawned[#M.spawned]
  ammo[w.alliance].handgun = 3
  for shot = 1, 2 do
    M.message(w, wa.msg.FIRE_WEAPON)
    w.state = "prefiring"
    M.message(w, wa.msg.FRAME_FINISH)
    w.aiming, w.state = false, nil
    for _ = 1, 4 do M.message(w, wa.msg.FRAME_FINISH) end
    M.quads = {}
    M.draw()
    check("the rifle and its laser stay up through shot " .. shot, not rifle.dead
      and rifle.scale == 1 and #M.quads > 0, tostring(#M.quads))
    w.aiming = true
    M.message(w, wa.msg.FRAME_FINISH)
  end
  check("still the same rifle after two shots", not rifle.dead and M.spawned[#M.spawned] == rifle)
end

print("sniper rifle: a muzzle flash on each shot")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  for _, o in ipairs(worms) do
    if o ~= w then o.x, o.y = -5000 * P, 0 end
  end
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim, w.turn, w.state =
    "handgun", 1, 100 * P, 50 * P, true, 0.5, true, nil
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local flash
  for _, a in ipairs(M.spawned) do
    if a.sprite == "sprites/sniper_rifle/flash" then flash = a end
  end
  check("a flash with the rifle, dark while it aims", flash and flash.shown == 0)
  ammo[w.alliance].handgun = 3
  M.message(w, wa.msg.FIRE_WEAPON)
  w.state = "prefiring"
  M.message(w, wa.msg.FRAME_FINISH)
  check("still dark through the wind-up", flash.shown == 0)
  w.aiming, w.state = false, nil
  local lit = {}
  for i = 1, 5 do
    M.message(w, wa.msg.FRAME_FINISH)
    lit[i] = flash.shown
  end
  check("lit for 3 frames from the shot", table.concat(lit, " ") == "1 1 1 0 0", table.concat(lit, " "))
  check("at the barrel's tip, 30 out and 2 to the side, pointing along the aim",
    flash.x == 130 * P and flash.y == 48 * P and flash.angle == 0, (flash.x / P) .. "," .. (flash.y / P))
  check("smaller than the sentry's, additive, white, in front of the rifle", flash.scale == 0.45
    and flash.blend == "add" and flash.tint == 0xFFFFFF and flash.depth < 0x10000)
  -- The second shot lights it again.
  w.aiming = true
  M.message(w, wa.msg.FRAME_FINISH)
  M.message(w, wa.msg.FIRE_WEAPON)
  w.aiming = false
  M.message(w, wa.msg.FRAME_FINISH)
  check("lit again by the next shot", flash.shown == 1)
  -- Facing left: mirrored with the worm.
  w.aiming, w.facing = true, -1
  for _ = 1, 4 do M.message(w, wa.msg.FRAME_FINISH) end
  check("facing left: 30 out to the left", flash.x == 70 * P and flash.facing == -1, tostring(flash.x / P))
  w.aiming = false
  w.state, w.weapon = "standing", "bazooka"
  M.message(w, wa.msg.FRAME_FINISH)
  check("dropped with the rifle", flash.dead)
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

print("double bazooka: a second shell carries on")
do
  new_match()
  frame()
  local P = 0x10000
  local spec
  for _, r in ipairs(replaced) do
    if r.weapon == "bazooka" then spec = r end
  end
  check("held as a plain bazooka: subtype_param stays stock (3), not the scheme's 7",
    not (spec.patch and spec.patch.subtype_param))
  check("the Double Bazooka on the bazooka slot, with its icon and an explode step", spec
    and spec.copy_from == "bazooka" and spec.panel_icon == "sprites/double_bazooka/double_bazooka_ico.png"
    and type(spec.on_explode) == "function")
  local w = worm(16)
  w.weapon = "bazooka"
  ammo[w.alliance].bazooka = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  M.missile({ id = 500, phase = "pre", weapon = "bazooka", x = 90 * P, y = 52 * P, vx = 0, vy = 0 })
  M.missile({ id = 500, phase = "post", weapon = "bazooka", x = 100 * P, y = 50 * P, vx = 6 * P, vy = -P })
  spec.on_explode({ x = 100 * P, y = 50 * P, slot = 1, missile = 500 })
  check("the first shell cuts PX's 50-pixel hole", M.digs and #M.digs == 1
    and M.digs[1].x == 100 * P and M.digs[1].y == 50 * P and M.digs[1].radius == 50)
  check("no second shell during the blast", not M.launched)
  M.message(worm(32), wa.msg.FRAME_FINISH)
  local l = M.launched and M.launched[1]
  check("a second shell after it, at the first one's speed, for the shooter", l and #M.launched == 1
    and l.weapon == "bazooka" and l.owner == w and l.x == 100 * P and l.y == 50 * P
    and l.vx == 6 * P and l.vy == -P)
  check("with PX's damage 40 and 5 s fuse, and the record's own bazooka shell (not PX's 54, a cluster bit here)",
    l.damage == 40 and l.fuse == 5000 and l.sprite == nil)
  M.message(worm(32), wa.msg.FRAME_FINISH)
  check("launched once", #M.launched == 1)
  M.missile({ id = 9001, phase = "post", weapon = "bazooka", x = 140 * P, y = 44 * P, vx = 6 * P, vy = 0 })
  spec.on_explode({ x = 140 * P, y = 44 * P, slot = 1, missile = 9001 })
  M.message(w, wa.msg.FRAME_FINISH)
  check("the second shell's explosion ends it", #M.launched == 1 and #M.digs == 1)
  spec.on_explode({ x = 1, y = 1, slot = 1 })
  spec.on_explode({ x = 1, y = 1, slot = 1, missile = 777 })
  M.message(w, wa.msg.FRAME_FINISH)
  check("no missile id, or one never seen flying: nothing", #M.launched == 1 and #M.digs == 1)
end

print("chilli bomb: five more Chillis burst out")
do
  new_match()
  frame()
  local P = 0x10000
  local spec
  for _, r in ipairs(replaced) do
    if r.weapon == "super_banana" then spec = r end
  end
  check("the Chilli Bomb on the super banana slot, with its icon, the banana kept, and an explode step", spec
    and spec.copy_from == "super_banana" and spec.panel_icon == "sprites/chilli_bomb/chilli_ico.png"
    and spec.sprite == "banana" and type(spec.on_explode) == "function")
  local w = worm(16)
  w.weapon = "super_banana"
  M.launched = nil
  M.message(w, wa.msg.FIRE_WEAPON)
  spec.on_explode({ x = 100 * P, y = 50 * P, slot = 42, missile = 600 })
  check("none during the blast", not M.launched)
  M.message(worm(32), wa.msg.FRAME_FINISH)
  local l = M.launched or {}
  local ok = #l == 5
  for _, c in ipairs(l) do
    ok = ok and c.weapon == "super_banana" and c.owner == w and c.x == 100 * P and c.y == 50 * P
      and c.vx >= -3 * P and c.vx <= 3 * P and c.vy >= -10 * P and c.vy <= -7 * P
  end
  check("five after it, for the thrower, up with PX's spread", ok, tostring(#l))
  local c = l[1] or {}
  check("each with damage 30, an 8 s fuse, no countdown, set off by the fire key, bursting into fire",
    c.damage == 30 and c.fuse == 8000 and c.countdown == 0 and c.explode_on_space == true
    and c.explode_into == "fire")
  check("and WA's sprite 0: only the chilli is drawn", c.sprite == 0)
  local m = { id = 610, phase = "pre", weapon = "super_banana", x = 0, y = 0, vx = P, vy = 0, sprite = 51 }
  M.missile(m)
  check("the thrown Chilli's own banana hidden in flight", m.sprite == 0)
  local b = { id = 611, phase = "pre", weapon = "bazooka", x = 0, y = 0, vx = P, vy = 0, sprite = 48 }
  M.missile(b)
  check("other missiles keep theirs", b.sprite == 48)
  M.message(worm(32), wa.msg.FRAME_FINISH)
  check("launched once", #M.launched == 5)
  for i = 1, 5 do
    spec.on_explode({ x = 1, y = 1, slot = 42, missile = 9000 + i })
  end
  M.message(w, wa.msg.FRAME_FINISH)
  check("the five do not burst again", #M.launched == 5)
  spec.on_explode({ x = 1, y = 1, slot = 42 })
  M.message(w, wa.msg.FRAME_FINISH)
  check("no missile id: nothing", #M.launched == 5)
end

print("nuke rocket: a nuke climbs out of the fusing rocket")
do
  new_match()
  frame()
  local P = 0x10000
  local spec
  for _, r in ipairs(replaced) do
    if r.weapon == "mine" then spec = r end
  end
  check("the Nuke Rocket on the mine slot, its icon, its rocket, an explode step", spec
    and spec.copy_from == "mine" and spec.panel_icon == "sprites/nuke_rocket/nuke_rocket_ico.png"
    and spec.sprite == "sprites/nuke_rocket/nuke_rocket_bullet.png" and type(spec.on_explode) == "function")
  check("its launch sound registered, so it can play", spec.sounds and spec.sounds[1] == "sounds/nuke_rocket_launch.wav")
  for _, o in ipairs(worms) do
    o.x, o.y, o.vx, o.vy = -5000 * P, 0, 0, 0
  end
  local w, near, far = worm(16), worm(17), worm(32)
  w.weapon, w.x, w.y = "mine", 60 * P, 50 * P
  near.x, near.y = 105 * P, 55 * P
  far.x, far.y = 300 * P, 50 * P
  M.message(w, wa.msg.FIRE_WEAPON)
  -- WA's own shot is the first rocket: it fuses on the ground, hissing.
  for _ = 1, 10 do
    M.missile({ id = 600, phase = "post", weapon = "mine", x = 100 * P, y = 50 * P, vx = 0, vy = 0 })
  end
  check("the fusing rocket hisses every 10 frames", #M.sounds == 1 and M.sounds[1] == 66,
    tostring(M.sounds[1]))
  spec.on_explode({ x = 100 * P, y = 50 * P, slot = 12, missile = 600 })
  check("its explosion plays PX's launch sound", M.sounds[2] == "sounds/nuke_rocket_launch.wav")
  check("no nuke during the blast", not M.launched)
  M.message(far, wa.msg.FRAME_FINISH)
  local l = M.launched and M.launched[1]
  check("then a nuke from there, for the shooter", l and #M.launched == 1 and l.weapon == "mine"
    and l.owner == w and l.x == 100 * P and l.y == 50 * P and l.vx == 0 and l.vy == 0)
  check("silent, a 1.6 s fuse, bursting into clustlets", l.fuse == 1600 and l.sound == 0
    and l.explode_into == "clustlets")
  local nuke = { id = 9001, phase = "pre", weapon = "mine", x = 100 * P, y = 50 * P, vx = 0, vy = 0 }
  local other = { id = 700, phase = "pre", weapon = "bazooka", x = 110 * P, y = 45 * P, vx = P, vy = 0 }
  local climb_ok, jitter = true, 0
  for t = 0, 52 do
    local vy, vx = nuke.vy, nuke.vx
    M.missile(nuke)
    local up = vy - nuke.vy
    if up < 19661 or up > 52429 then climb_ok = false end
    if nuke.vx ~= vx then
      jitter = jitter + 1
      if t % 2 == 0 then climb_ok = false end
    end
    if t == 0 then
      M.missile(other)
      check("a missile within 17 pixels is carried along", other.vx == nuke.vx and other.vy == nuke.vy)
      check("so is a worm, but not one further off", near.vx == nuke.vx and near.vy == nuke.vy
        and far.vx == 0 and far.vy == 0)
    end
  end
  check("for 53 frames it climbs 0.3 to 0.8 a frame, jittering sideways on every other", climb_ok
    and jitter > 0)
  local vy = nuke.vy
  M.missile(nuke)
  check("then it brakes by 0.2 a frame", nuke.vy == vy + 13107, tostring((nuke.vy - vy) / P))
  local sounds = #M.sounds
  for _ = 1, 10 do
    M.missile({ id = 800, phase = "post", weapon = "mine", x = 90 * P, y = 40 * P, vx = 0, vy = 0 })
  end
  check("later missiles of the slot (the cluster bits) are no fusing rocket: no hiss", #M.sounds == sounds)
  M.sounds = {}
  local before = M.spawned and #M.spawned or 0
  spec.on_explode({ x = 100 * P, y = -200 * P, slot = 12, missile = 9001 })
  M.message(far, wa.msg.FRAME_FINISH)
  check("its explosion: sounds 85 and 70, and two 40/40 blasts", M.sounds[1] == 85 and M.sounds[2] == 70
    and #M.spawned == before + 2 and M.spawned[before + 1].explode.damage == 40
    and M.spawned[before + 1].explode.id == 40 and M.spawned[before + 2].explode.now)
  check("and it ends there", #M.launched == 1)
end

print("nuke rocket: held at a fixed angle, as PX's sprite builder does")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.facing, w.x, w.y, w.aiming, w.aim, w.turn, w.state =
    "mine", 1, 100 * P, 50 * P, true, 0.2, true, nil
  for _ = 1, 25 do M.message(w, wa.msg.FRAME_FINISH) end
  local rocket, hand = M.spawned[#M.spawned - 1], M.spawned[#M.spawned]
  check("the rocket and a hand", rocket.sprite == "sprites/px_hold/nuke_rocket"
    and hand.sprite == "sprites/px_hold/hand_rad")
  local function deg(a) return math.floor(a + 0.5) % 360 end
  check("turned by PX's fixed angles: -0.1 pi and 0.4 pi", deg(rocket.angle) == 342 and deg(hand.angle) == 72,
    rocket.angle .. " " .. hand.angle)
  local x = rocket.x
  w.aim = 0.9
  M.message(w, wa.msg.FRAME_FINISH)
  check("whatever the aim", deg(rocket.angle) == 342 and rocket.x == x)
  w.facing = -1
  M.message(w, wa.msg.FRAME_FINISH)
  check("mirrored facing left", deg(rocket.angle) == 18 and deg(hand.angle) == 288 and rocket.facing == -1,
    rocket.angle .. " " .. hand.angle)
end

print("helicopter: PX's script on WA's jet pack")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.facing, w.turn = "jet_pack", "prefiring", 100 * P, 50 * P, 0, 0, 1, true
  w.fuel, w.gravity, w.wind, w.body_visible = 30 * P, P, 0, true
  w.keys = { up = false, down = false, left = false, right = false }
  function w:clear_keys() self.keys = { up = false, down = false, left = false, right = false }; self.cleared = true end
  function w:set_state(s) self.state = s end
  M.spawned = {}
  M.message(w, wa.msg.FRAME_FINISH)
  local climb = M.spawned[#M.spawned]
  check("the climb-in while WA winds up, the body hidden, the labels kept", climb and climb.sprite == "sprites/helicopter/jumpin"
    and w.body_visible == false and w.visible == nil)
  w.state = "jetpacking"
  w.keys.up = true
  M.message(w, wa.msg.FRAME_FINISH)
  check("launch: PX's fuel, gravity and wind", w.fuel < 100 * P and w.fuel > 99 * P and w.gravity == math.floor(0.2 * P)
    and w.wind == math.floor(0.2 * P), w.fuel / P .. " " .. w.gravity .. " " .. w.wind)
  check("up: a kick of 0.8 from standstill", w.vy == -math.floor(0.8 * P) - 0 or w.vy == -52428, tostring(w.vy))
  check("its keys consumed, so WA's jet pack does nothing", w.cleared and not w.keys.up)
  check("the helicopter replaces the climb-in", climb.dead and M.spawned[#M.spawned].sprite == "sprites/helicopter/flying")
  local vy = w.vy
  M.message(w, wa.msg.FRAME_FINISH)
  check("no key: speed dies away", w.vy > vy and w.vy < 0, vy .. " -> " .. w.vy)
  local fuel = w.fuel
  M.retreat = 2000
  M.message(w, wa.msg.FRAME_FINISH)
  check("no fuel burnt during retreat", w.fuel == fuel)
  M.retreat = 0
  -- Hitting a mine is fine; hitting a worm fast is not.
  M.contact(w, { kind = "mine" }, { vx = 3 * P, vy = 0, flags = 0 })
  check("a mine does not crash it", #M.spawned == 2)
  M.contact(w, { kind = "worm" }, { vx = P // 2, vy = 0, flags = 0 })
  check("a slow touch does not crash it", #M.spawned == 2)
  M.contact(w, { kind = "land" }, { vx = 0, vy = P // 2, flags = 0 })
  check("a slow landing does not crash it: PX's smooth landing", #M.spawned == 2)
  M.contact(w, { kind = "worm" }, { vx = 3 * P, vy = 0, flags = 0 })
  local boom = M.spawned[#M.spawned]
  check("a fast hit crashes it: an explosion of at least 10", boom.explode and boom.explode.id == 10
    and boom.explode.damage == 20 and boom.explode.now, boom.explode and boom.explode.id)
  -- From wa.on.contact there is no brain to inherit an owner from.
  check("the explosion is the worm's own", boom.owner == w)
  check("and lands the worm, shown again", w.gravity == P and w.wind == 0 and w.body_visible == true)
  -- Out of fuel.
  w.state = "prefiring"
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "jetpacking"
  M.message(w, wa.msg.FRAME_FINISH)
  local n = #M.spawned
  w.fuel = math.floor(0.05 * P)
  M.message(w, wa.msg.FRAME_FINISH)
  check("fuel below 0.1 crashes it", #M.spawned == n + 1 and M.spawned[#M.spawned].explode)
  -- WA ends the jet pack on the ground: slide, no crash.
  w.state = "prefiring"
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "jetpacking"
  M.message(w, wa.msg.FRAME_FINISH)
  w.fuel, w.vy, w.vx = 50 * P, 0, 0
  w.state = "standing"
  n = #M.spawned
  M.message(w, wa.msg.FRAME_FINISH)
  check("WA ends the jet pack at rest: sliding, no explosion", w.state == "sliding" and #M.spawned == n
    and w.gravity == P)
  -- The last Helicopter: WA clears the selection when it fires.
  w.state, w.weapon, w.vy = "prefiring", "jet_pack", 0
  M.message(w, wa.msg.FRAME_FINISH)
  w.state, w.weapon = "jetpacking", nil
  M.message(w, wa.msg.FRAME_FINISH)
  check("the last one still flies: armed in the wind-up", w.fuel > 99 * P, tostring(w.fuel / P))
  local before = #M.spawned
  M.contact(w, { kind = "land" }, { vx = 0, vy = 3 * P, flags = 0 })
  check("a fast landing crashes it, as in PX", #M.spawned == before + 1 and M.spawned[#M.spawned].explode)
end

print("hot air balloon: PX's balloon on WA's parachute")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.facing, w.turn = "bungee", "sliding", 100 * P, 50 * P, 0, P, 1, true
  w.gravity, w.body_visible, w.alliance, w.keys = P, true, 1, {}
  for i, o in ipairs(worms) do
    if o ~= w then o.x, o.y = -1000 * P * i, 0 end
  end
  function w:set_state(s) self.state = s end
  M.spawned, M.sounds = {}, {}
  M.message(w, wa.msg.FRAME_FINISH)
  check("nothing while it just falls", #M.spawned == 0 and w.gravity == P)
  -- WA opens the parachute and clears the selection: "none", as seen in WA.
  w.state, w.weapon = "parachuting", "none"
  M.message(w, wa.msg.FRAME_FINISH)
  check("up: gravity turned over", w.gravity == -P, tostring(w.gravity))
  check("an inflate sound", M.sounds[1] and M.sounds[1]:find("inflate"))
  local balloon, basket = M.spawned[1], M.spawned[2]
  check("the balloon in the team's colour, the basket below", balloon.sprite == "sprites/balloon/balloon"
    and balloon.tint == 0xFF0096FF and basket.sprite == "sprites/balloon/basket" and w.body_visible == false,
    string.format("%x", balloon.tint or 0))
  check("the balloon 43 above, 6 ahead; the basket's art mirrored facing right",
    balloon.y == w.y - 43 * P and balloon.x == w.x + 6 * P and basket.facing == -1)
  -- The parachute closes on the ground: slide, pop, gravity back.
  w.state = "standing"
  M.message(w, wa.msg.FRAME_FINISH)
  check("closed: gravity back, sliding, popped", w.gravity == P and w.state == "sliding"
    and M.sounds[#M.sounds]:find("pop") and balloon.dead and w.body_visible == true)
  -- Up again, then the turn changes.
  w.state, w.weapon = "sliding", "bungee"
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  check("up again", w.gravity == -P)
  M.turn_start({ worm = worm(32), active = worm(32) })
  check("a turn change pops it", w.gravity == P)
  -- The Hang-Glider's parachute is not a balloon.
  w.state, w.weapon = "sliding", "parachute"
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  check("another slot's parachute is left alone", w.gravity == P)
end

print("hang-glider: PX's glider on WA's parachute")
do
  new_match()
  frame()
  local P = 0x10000
  M.gravity, M.wind, M.trace_hit = 0x3AE, 0, nil -- a small pull, as WA's is
  for i, o in ipairs(worms) do o.x, o.y = -1000 * P * i, 0 end
  local w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.facing, w.turn = "parachute", "sliding", 100 * P, 50 * P, 3 * P, P, 1, true
  w.body_visible, w.keys = true, {}
  function w:set_state(s) self.state = s end
  M.spawned, M.sounds = {}, {}
  M.message(w, wa.msg.FRAME_FINISH)
  check("nothing while it just falls", #M.spawned == 0 and w.body_visible == true)
  -- WA opens the parachute and clears the selection.
  w.state, w.weapon = "parachuting", "none"
  M.message(w, wa.msg.FRAME_FINISH)
  local art = M.spawned[1]
  check("opens: the glider sound and art, the body hidden", M.sounds[1] and M.sounds[1]:find("hangopen")
    and art and art.sprite == "sprites/hang_glider/glider" and w.body_visible == false)
  check("its art faces left, as WA's worms: mirrored facing right", art.facing == -1)
  -- Level, the wing's up side is straight up: a quarter of the fall goes.
  check("the speed carries on into the glide; the wing takes a quarter of the fall",
    math.abs(w.vx - 3 * P) <= 1 and math.abs(w.vy - (1 + 0x3AE * 0.75 / P) * 0.75 * P) <= 1, w.vx .. " " .. w.vy)
  for _ = 1, 30 do M.message(w, wa.msg.FRAME_FINISH) end
  check("and the nose follows the flight path", art.angle ~= 0, tostring(art.angle))
  check("it opens over 25 frames", art.shown == 9, tostring(art.shown))
  -- Nose up: the nose angle drops, faster the faster it flies.
  w.keys = { up = true }
  for _ = 1, 10 do M.message(w, wa.msg.FRAME_FINISH) end
  w.keys = {}
  check("up turns the nose up", art.angle and art.angle > 180, tostring(art.angle))
  -- Heading into the ground: it stops gliding, as PX's WS_AFTERROPE.
  M.trace_hit = { x = w.x, y = w.y }
  M.message(w, wa.msg.FRAME_FINISH)
  check("about to hit something: it slides", w.state == "sliding")
  M.trace_hit = nil
  M.message(w, wa.msg.FRAME_FINISH)
  check("closed: the sound, the art gone, the body back, no pack-away",
    M.sounds[#M.sounds]:find("hangclose") and art.dead and w.body_visible == true and #M.spawned == 1)
  -- Up again (the weapon was the glider), then a landing on its feet.
  w.state = "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "standing"
  M.message(w, wa.msg.FRAME_FINISH)
  local pack = M.spawned[#M.spawned]
  check("landed: the glider's own pack-away over the hidden body",
    pack.sprite == "sprites/hang_glider/pack" and w.body_visible == false and pack.facing == -1)
  for _ = 1, 12 do M.message(w, wa.msg.FRAME_FINISH) end
  check("six frames at 24 a second", pack.shown == 5 and not pack.dead, tostring(pack.shown))
  M.message(w, wa.msg.FRAME_FINISH)
  check("then the worm again", pack.dead and w.body_visible == true)
  -- The balloon's parachute is not a glider.
  w.weapon = "bungee"
  M.message(w, wa.msg.FRAME_FINISH)
  local n = #M.spawned
  w.state = "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  local glider = false
  for i = n + 1, #M.spawned do
    if M.spawned[i].sprite == "sprites/hang_glider/glider" then glider = true end
  end
  check("the Hot Air Balloon's parachute is left alone", not glider)
end

print("swim suit: PX's swimming on WA's laser sight")
do
  new_match()
  frame()
  local P = 0x10000
  M.water = 500 * P
  local w = worm(16)
  for i, o in ipairs(worms) do
    if o ~= w then o.x, o.y, o.turn = -1000 * P * i, 0, false end
  end
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.facing, w.turn = "laser_sight", "standing", 100 * P, 400 * P, 0, 0, 1, true
  w.gravity, w.body_visible, w.keys, w.collision_mask = P, true, {}, 0x420CC6
  function w:set_state(s) self.state = s end
  function w:clear_keys() self.keys = {} end
  local spent = 0
  function w:ammo(slot, n) if slot == "laser_sight" then spent = spent + n end end
  M.spawned, M.sounds, M.quads = {}, {}, {}
  check("putting it on replaces WA's laser sight", M.message(w, wa.msg.FIRE_WEAPON) == "eat" and spent == -1)
  check("the suit's mask: without the bit WA's water acts on", w.collision_mask == 134342)
  check("its sound", M.sounds[#M.sounds] == "sounds/swim_suit/putting_on_ssuit.wav")
  M.message(w, wa.msg.FRAME_FINISH)
  M.draw()
  check("a bubble while worn", #M.quads == 1 and M.quads[1].sprite == "sprites/swim_suit/ring")
  local bubble = M.quads[1]
  local h = 25 * P
  check("centred on the worm", bubble.points[1][1] == w.x - h and bubble.points[3][1] == w.x + h
    and bubble.points[1][2] == w.y - h and bubble.points[3][2] == w.y + h)
  -- Into the water, falling fast: a splash, no gravity, the speed capped, a
  -- bungee's state.
  w.state, w.y, w.vx, w.vy = "sliding", 510 * P, 9 * P, 12 * P
  M.message(w, wa.msg.FRAME_FINISH)
  check("splash, no gravity, swimming", M.sounds[#M.sounds] == 57 and w.gravity == 0 and w.state == "bungee")
  check("the speed capped at 5 (2.5 times the swim speed 2), then eased", w.vx < 5 * P and w.vy < 5 * P
    and w.vx > 4 * P, w.vx .. " " .. w.vy)
  check("the swim animation in its place, facing left art mirrored", w.body_visible == false
    and M.spawned[#M.spawned].sprite == "sprites/swim_suit/swim" and M.spawned[#M.spawned].facing == -1)
  -- Swimming left: a push, turned, and the key used up.
  w.vx, w.vy, w.keys = 0, 0, { left = true }
  M.message(w, wa.msg.FRAME_FINISH)
  check("left: 0.2 a frame that way, facing it, the key taken", w.vx == -13107 and w.facing == -1
    and not w.keys.left, tostring(w.vx))
  check("no jumping while it swims", M.message(w, wa.msg.JUMP) == "eat")
  -- Still, no key: the float animation.
  w.vx, w.vy = 0, 0
  M.message(w, wa.msg.FRAME_FINISH)
  M.message(w, wa.msg.FRAME_FINISH)
  check("still: floating", M.spawned[#M.spawned].sprite == "sprites/swim_suit/float")
  -- Out of the water: on as from a jump, gravity back.
  w.y, w.vy = 490 * P, -2 * P
  M.message(w, wa.msg.FRAME_FINISH)
  check("out: airborne, gravity back, the suit still on", w.state == "sliding" and w.gravity == P
    and w.collision_mask == 134342)
  -- Back in, then too deep: it gives out and the worm sinks.
  w.y = 510 * P
  M.message(w, wa.msg.FRAME_FINISH)
  w.y = 700 * P
  M.message(w, wa.msg.FRAME_FINISH)
  check("too deep: sinking, the water's bit back in its mask, drawn as itself", w.state == "sinking"
    and w.collision_mask == 134342 | 0x400000 and w.body_visible == true)
  -- Fast Walk: swim speed 6 for the turn.
  w.weapon = "fast_walk"
  M.message(w, wa.msg.FIRE_WEAPON)
  w.weapon, w.state, w.y, w.vx, w.vy = "laser_sight", "sliding", 400 * P, 0, 0
  M.message(w, wa.msg.FIRE_WEAPON)
  w.y, w.vx, w.vy = 510 * P, 20 * P, 0
  M.message(w, wa.msg.FRAME_FINISH)
  check("Fast Walk: capped at 15", w.vx > 14 * P and w.vx <= 15 * P, tostring(w.vx / P))
  -- A missile in the water hits worms, and blows up on a swimmer.
  local m = { id = 1, phase = "pre", weapon = "bazooka", x = 0, y = 0, vx = 0, vy = 0, collision_mask = 0x400000 }
  M.missile(m)
  check("a missile in the water also hits worms", m.collision_mask == 0x40007C)
  local n = #M.spawned
  local missile = { kind = "missile", x = 120 * P, y = 520 * P }
  M.contact(w, missile, { vx = 0, vy = 0, flags = 0 })
  local boom = M.spawned[n + 1]
  check("it blows up on the swimmer (100, 50) and is gone", boom and boom.explode and boom.explode.damage == 100
    and boom.explode.id == 50 and missile.y > M.water)
  M.turn_start({ worm = w, active = w })
end

print("wind changer and gravity control: 0-9 and 1-5, then fire")
do
  new_match()
  M.gravity, M.wind, M.digit = 0x3AE, 0, nil
  frame()
  local P = 0x10000
  M.sounds = {}
  local w = worm(16)
  for _, o in ipairs(worms) do o.turn = false end
  w.turn, w.facing, w.weapon = true, -1, "surrender"
  -- Choose 7: once, on the key going down.
  M.digit = 7
  M.message(w, wa.msg.FRAME_FINISH)
  M.message(w, wa.msg.FRAME_FINISH)
  check("a digit counts once, when it goes down", #M.sounds == 1 and M.sounds[1] == 107)
  M.hud_lines = {}
  M.hud()
  check("the HUD says the force and the keys", M.hud_lines[1] and M.hud_lines[1]:find("force 7"))
  M.digit = nil
  check("firing it goes on to WA's no-op utility", M.message(w, wa.msg.FIRE_WEAPON) == nil)
  check("wind 7 x 0.0317 towards where the worm faces, a strong wind (6 and up)",
    M.wind == -math.floor(7 * 0.0317 * P) and M.sounds[#M.sounds] == "sounds/wind_changer/strong_wind.wav",
    tostring(M.wind) .. " " .. tostring(M.sounds[#M.sounds]))
  -- Gravity Control: nothing chosen, no shot.
  w.weapon = "low_gravity"
  check("nothing chosen: not fired, an error sound", M.message(w, wa.msg.FIRE_WEAPON) == "eat"
    and M.sounds[#M.sounds] == "sounds/gravity_control/error.wav" and M.gravity == 0x3AE)
  M.digit = 9
  M.message(w, wa.msg.FRAME_FINISH)
  M.digit = 5
  M.message(w, wa.msg.FRAME_FINISH)
  M.digit = nil
  M.message(w, wa.msg.FRAME_FINISH)
  check("5: very high gravity chosen (9 means nothing)", M.message(w, wa.msg.FIRE_WEAPON) == nil
    and M.gravity == math.floor(0x3AE * 2.4), tostring(M.gravity))
  M.turn_start({ worm = w, active = w })
  check("the next turn: the match's gravity", M.gravity == 0x3AE)
end

print("jump: the worm leaves with the shot")
do
  new_match()
  frame()
  local P = 0x10000
  local spec
  for _, r in ipairs(replaced) do
    if r.weapon == "ninja_rope" then spec = r end
  end
  check("on the ninja rope's slot, PX's record and aim sheets", spec and spec.copy_from == "ninja_rope"
    and spec.worm_sprites.weaponlnk == "sprites/jump/aim" and type(spec.on_fire) == "function")
  local w = worm(33)
  w.turn, w.weapon, w.facing, w.body_visible = true, "ninja_rope", 1, true
  w.x, w.y, w.vx, w.vy, w.state = 100 * P, 50 * P, 0, 0, "standing"
  function w:set_state(s) self.state = s end
  M.spawned, M.sounds = {}, {}
  M.message(w, wa.msg.FIRE_WEAPON)
  M.message(w, wa.msg.FRAME_FINISH)
  check("charging: the worm keeps its aim posture", #M.spawned == 0 and w.body_visible)
  spec.on_fire({ worm = w, x = w.x, y = w.y, vx = 3 * P, vy = -5 * P })
  check("fired: the shot's speed, airborne", w.vx == 3 * P and w.vy == -5 * P and w.state == "sliding")
  check("the team's Jump line: team 2's bank", M.sounds[#M.sounds] == 150 + 54, tostring(M.sounds[#M.sounds]))
end

print("px missile sprites: WeapSprite at run time")
do
  new_match()
  frame()
  local PX = 0x10000
  local m = { id = 77, phase = "post", weapon = "longbow", x = 10 * PX, y = 20 * PX, vx = 3 * PX, vy = 0 }
  M.missile(m)
  check("no current worm: nothing drawn (PX's WeapSprite needs one)", not M.spawned)
  local shooter = worm(16)
  shooter.turn = true
  M.missile(m)
  local bolt = M.spawned and M.spawned[#M.spawned]
  check("a bolt on the Shadow-Bolt's missile, owned by the current worm", bolt
    and bolt.sprite == "sprites/shadow_bolt/bolt" and bolt.x == m.x and bolt.y == m.y
    and bolt.owner == shooter)
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

  -- The Igniter's bullet, climbing up and to the left: turned, not upright.
  m.weapon, m.id, m.vx, m.vy = "homing_missile", 79, -3 * PX, -3 * PX
  M.missile(m)
  local bullet = M.spawned[#M.spawned]
  check("a bullet on the Igniter's missile", #M.spawned == before + 1
    and bullet.sprite == "sprites/igniter/flight")
  check("turned to its flight, mirrored flying left", bullet.facing == -1
    and math.abs(bullet.angle - 315) < 1e-6, tostring(bullet.angle))
  shown = {}
  for _ = 1, 40 do
    M.missile(m)
    shown[bullet.shown] = true
  end
  check("steps through all sixteen frames", shown[0] and shown[15])
end

print("pack sounds: every WAV registered")
do
  local missing = {}
  for name in pairs(unregistered_sounds) do missing[#missing + 1] = name end
  table.sort(missing)
  check("every pack sound the rules played is registered", #missing == 0, table.concat(missing, ", "))
  -- And every WAV in the pack, where the suite can list its folder.
  local ls = io and io.popen and io.popen("find mods/examples/highlander/sounds -name '*.wav' 2>/dev/null")
  if ls then
    new_match()
    local registered, unlisted = {}, {}
    for _, r in ipairs(replaced) do
      for _, snd in ipairs(r.sounds or {}) do registered[snd] = true end
    end
    local found = 0
    for line in ls:lines() do
      local rel = line:match("mods/examples/highlander/(.*)")
      found = found + 1
      if rel and not registered[rel] then unlisted[#unlisted + 1] = rel end
    end
    ls:close()
    if found > 0 then
      table.sort(unlisted)
      check("every WAV in sounds/ is registered by an entry", #unlisted == 0, table.concat(unlisted, ", "))
    end
  end
end

print("")
if fails == 0 then
  print("ALL PASS")
else
  print(("%d FAILED"):format(fails))
  os.exit(1)
end
