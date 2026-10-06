-- Drives mods/examples/highlander/rules.lua against a mocked WA.
--
--   lua mods/examples/highlander/test_rules.lua              (from the repo root)
--   lua mods/examples/highlander/test_rules.lua --baseline   (rewrites baseline.txt)
--
-- baseline.txt is the pack's observable shape: every slot it claims and what
-- with, the hooks it registers, the globals it defines, and what each hand can
-- be dealt. Every run compares against it, so a refactor that changes any of
-- it fails until baseline.txt is rewritten on purpose.

-- The globals Lua itself defines, before this file or the pack adds any.
local PRISTINE = {}
for k in pairs(_G) do
  PRISTINE[k] = true
end
--
-- The pack is data, not a crate, so this is not part of `cargo test`. Ammo
-- is modelled per ammo group, as WA stores it, and `{ set = n }` is
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
  local store = ammo[self.ammo_group]
  if change == nil then
    return store[name] or 0
  end
  assert(type(change) == "table" and change.set, "rules must only ever SET ammo")
  store[name] = change.set
  return change.set
end
function Worm:heal(amount) if self.hp > 0 then self.hp = self.hp + amount end end
function Worm:hurt(amount) self.hp = math.max(0, self.hp - amount) end
function Worm:carry(x, y) self.x, self.y, self.carried = x, y, true end
function Worm:drop() self.carried = false end
function Worm:clear_keys() self.keys = {} end
function Worm:set_state(state) self.state = state end
function Worm:freeze()
  if self.hp <= 0 or self.state == "frozen" then return false end
  self.state = "frozen"
  return true
end
-- The engine's handoff verbs: what the worm looks like to the pack after.
function Worm:take(opts)
  opts = opts or {}
  self.taken = { hide = opts.hide or false, turn = opts.turn or "run" }
  if opts.hide then self.visible = false end
end
function Worm:release(vx, vy, opts)
  self.taken, self.carried = nil, false
  if self.visible == false then self.visible = true end
  self.state = opts and opts.tumble and "tumbling" or "sliding"
  self.vx, self.vy = vx or 0, vy or 0
  self.release_options = opts
end
function Worm:jetpack_steer(on) self.steered = on ~= false end
-- WA's collision test, in the mock: the land M.solid gives, 4 pixels either
-- side of the worm and 6 above and below.
function Worm:fits(x, y)
  if not M.solid then return true end
  local w, h = 4 * 0x10000, 6 * 0x10000
  return not (M.solid(x, y) or M.solid(x - w, y) or M.solid(x + w, y)
    or M.solid(x, y - h) or M.solid(x, y + h))
end

-- A copy of `v` and every table in it.
local function deep_copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deep_copy(x) end
  return out
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
          if not seen[live.ammo_group] then
            seen[live.ammo_group] = true
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
  rng = opts.seed or rng
  -- Two teams of two, each its own alliance: team 1 is alliance 0, team 2 is 1.
  -- `per_team` makes larger teams, numbered team * 1000 + index.
  local per_team = opts.per_team or 2
  for team = 1, 2 do
    ammo[team - 1] = {}
    for index = 0, per_team - 1 do
      worms[#worms + 1] = setmetatable({
        id = (per_team > 2 and team * 1000 or team * 16) + index, team = team,
        alliance = team - 1, ammo_group = team - 1, hp = 100,
        kind = "worm", x = 0, y = 0, facing = 1,
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
    sorted = function(t)
      local out = {}
      for k in pairs(t) do out[#out + 1] = k end
      table.sort(out)
      return out
    end,
    log = function(s) logs[#logs + 1] = s end,
    hud = { line = function(text) M.hud_lines = M.hud_lines or {}; M.hud_lines[#M.hud_lines + 1] = text end },
    msg = { FRAME_FINISH = 2, START_TURN = 0x34, FIRE_WEAPON = 0x26, JUMP = 0x24 },
    world = {
      cavern = function() return cavern end,
      retreat = function() return M.retreat or 0 end,
      turn_clock = function() return M.turn_clock or 0 end,
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
    mines = { all = function() return M.mines end },
    crates = { all = function() return M.crates end },
    oil = { all = function() return M.oil end },
    graves = { all = function() return M.graves end },
    inventory = inventory_api(),
    land = {
      stamp = function(spec) M.stamps = M.stamps or {}; M.stamps[#M.stamps + 1] = spec end,
      cut = function(spec)
        M.cuts = M.cuts or {}
        M.cuts[#M.cuts + 1] = spec
      end,
      dig = function(spec)
        M.digs = M.digs or {}
        M.digs[#M.digs + 1] = spec
      end,
      trace = function(...)
        if type(M.trace_hit) == "function" then return M.trace_hit(...) end
        return M.trace_hit
      end,
      solid = function(x, y) return M.solid ~= nil and M.solid(x, y) or false end,
    },
    draw = {
      -- The engine reads the table before returning, so a pack may refill
      -- one table for every call: keep a copy, as the engine does.
      quad = function(q) M.quads[#M.quads + 1] = deep_copy(q) end,
      ribbon = function(q) M.ribbons[#M.ribbons + 1] = deep_copy(q) end,
      random = function() return 0.5 end,
    },
    sound = {
      play = function(target, name, flags)
        M.sound_targets = M.sound_targets or {}
        M.sound_targets[#M.sound_targets + 1] = target
        M.sounds[#M.sounds + 1] = name
        M.sound_flags[#M.sound_flags + 1] = flags
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
        local a = { sprite = spec.sprite, x = spec.x, y = spec.y, dead = false, explode = spec.explode, on = spec.on,
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
      -- Every handler, in registration order, as the engine keeps them,
      -- each run only for the messages it names (no options: every one).
      worm_message = function(f, opts)
        M.handlers = M.handlers or {}
        M.handler_msgs = M.handler_msgs or {}
        local wants = false
        if opts then
          assert(type(opts.msgs) == "table" and #opts.msgs > 0, "worm_message: msgs = { ... }")
          wants = {}
          for _, m in ipairs(opts.msgs) do
            assert(math.type(m) == "integer", "worm_message: msgs lists message numbers")
            wants[m] = true
          end
        end
        M.handlers[#M.handlers + 1] = f
        M.handler_msgs[#M.handlers] = wants
        -- "eat" from any handler swallows the message, as the engine's.
        M.message = function(w, msg)
          local eat
          for i, h in ipairs(M.handlers) do
            local wanted = M.handler_msgs[i]
            if not wanted or wanted[msg] then
              if h(w, msg) == "eat" then eat = "eat" end
            end
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
      turn_end = function(f)
        M.turn_ends = M.turn_ends or {}
        M.turn_ends[#M.turn_ends + 1] = f
        M.turn_end = function(...)
          for _, h in ipairs(M.turn_ends) do h(...) end
        end
      end,
      missile_frame = function(f)
        M.missile_handlers = M.missile_handlers or {}
        M.missile_handlers[#M.missile_handlers + 1] = f
        M.missile = function(m)
          for _, h in ipairs(M.missile_handlers) do h(m) end
        end
      end,
      hurt = function(f)
        M.hurt_handlers = M.hurt_handlers or {}
        M.hurt_handlers[#M.hurt_handlers + 1] = f
        M.hurt = function(hit)
          for _, h in ipairs(M.hurt_handlers) do h(hit) end
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
  M.quads, M.ribbons, M.sounds, M.sound_flags, M.trace_hit, M.draws = {}, {}, {}, {}, nil, nil
  M.mines, M.crates, M.oil, M.graves = {}, {}, {}, {}
  -- The engine's require: a pack module runs once per match, in its own
  -- environment that reads the shared globals and keeps its writes.
  local modules = {}
  function require(name)
    if modules[name] ~= nil then return modules[name] end
    local env = setmetatable({}, { __index = _G })
    local root = HIGHLANDER_ROOT or "mods/examples/highlander/"
    local chunk = assert(loadfile(root .. name .. ".lua", "t", env))
    local result = chunk()
    if result == nil then result = true end
    modules[name] = result
    return result
  end
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
  check("56 slots replaced, each once", #replaced == 56 and not dupes, tostring(#replaced))
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
    if slot == "earthquake" or slot == "napalm_strike" or slot == "teleport" or slot == "uzi" or slot == "prod" or slot == "armageddon" then
      if spec.wep ~= "weps/" .. slot .. ".wep" or spec.copy_from then own_file = false end
    elseif spec.copy_from ~= slot or spec.wep then own_file = false end
  end
  check("scheme records use their intended bases; others copy stock", own_file)
  check("Skip Go uses stock Skip Go, with Ctrl choosing stock Surrender",
    by_slot.skip_go and by_slot.skip_go.copy_from == "skip_go"
      and by_slot.skip_go.name == "Skip Go/Surrender"
      and by_slot.skip_go.panel_icon == "sprites/skip_go/icon.png"
      and by_slot.skip_go.stock_fire_choice.held == "ctrl"
      and by_slot.skip_go.stock_fire_choice.alternate == "surrender")
  check("Ice Arrow uses PX's arrow record and icon",
    by_slot.armageddon and by_slot.armageddon.wep == "weps/armageddon.wep"
      and by_slot.armageddon.panel_icon == "sprites/ice_arrow/icon.png")
  check("Super Tele owns the teleport cursor and click dispatch",
    by_slot.teleport and by_slot.teleport.on_select.cursor
      and type(by_slot.teleport.on_click) == "function"
      and by_slot.teleport.panel_icon == "sprites/super_tele/icon.png")
  check("Lightning Strike claims the stock land cursor and click dispatch",
    by_slot.napalm_strike and by_slot.napalm_strike.on_select.cursor
      and type(by_slot.napalm_strike.on_click) == "function")
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

print("Ice Arrow: only its own arrow freezes after the bow hit")
do
  new_match()
  local target, other = worm(32), worm(17)
  target.state, target.vx = "tumbling", 3 * 0x10000
  M.hurt({ phase = "post", source_weapon = "longbow", kind = "hit", worm = other })
  M.hurt({ phase = "pre", source_weapon = "armageddon", kind = "hit", worm = other })
  M.hurt({ phase = "post", source_weapon = "armageddon", kind = "hit", worm = target })
  check("bow impulse remains until the target's next frame",
    target.state == "tumbling" and target.vx == 3 * 0x10000 and other.state ~= "frozen")
  M.message(other, wa.msg.FRAME_FINISH)
  M.message(target, wa.msg.FRAME_FINISH)
  check("the hit target alone enters frozen state", target.state == "frozen" and other.state ~= "frozen")
  target.state, target.hp = "tumbling", 0
  M.hurt({ phase = "post", source_weapon = "armageddon", kind = "hit", worm = target })
  M.message(target, wa.msg.FRAME_FINISH)
  check("a later hit cannot freeze a dead worm", target.state == "tumbling")
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
  ammo[w.ammo_group].fire_punch = 1
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
  ammo[w.ammo_group].fire_punch = 1
  M.message(w, wa.msg.FIRE_WEAPON)
  for _ = 1, 100 do M.message(w, wa.msg.FRAME_FINISH) end
  w.vy = -3 * 0x10000 -- a later jump of some other kind
  M.message(w, wa.msg.FRAME_FINISH)
  check("is forgotten", w.vy == -3 * 0x10000, tostring(w.vy))
end

print("px holds: each replacement carries declarative engine hold data")
do
  new_match()
  local holds = {}
  for _, spec in ipairs(replaced) do
    if spec.hold then holds[spec.weapon] = spec.hold end
  end
  local count = 0
  for _ in pairs(holds) do count = count + 1 end
  check("eight PX holds claimed", count == 8, tostring(count))
  check("Sticky Bomb has a weapon and the lower radial hand",
    holds.grenade.sheet == "sprites/px_hold/sticky_bomb"
    and holds.grenade.hand == "sprites/px_hold/hand_rad_lower"
    and holds.grenade.thrown)
  check("Shadow-Bolt animates with no hand",
    holds.longbow.sheet == "sprites/px_hold/shadow_bolt"
    and holds.longbow.hand == nil and holds.longbow.frames == 6)
  check("Sniper Rifle keeps its shot hold and flash",
    holds.handgun.keep_while_firing and holds.handgun.flash.sheet == "sprites/sniper_rifle/flash"
    and holds.handgun.hand == nil)
  check("Nuke Rocket uses PX's fixed angles",
    holds.mine.static.weap == -0.1 and holds.mine.static.hand == 0.4
    and holds.mine.hand == "sprites/px_hold/hand_rad")
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
  ammo[w.ammo_group].handgun = 1
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
  ammo[w.ammo_group].bazooka = 1
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

print("s.m.a.r.t bomb: homing bits leave the red trail")
do
  new_match()
  local spec
  for _, r in ipairs(replaced) do
    if r.weapon == "mortar" then spec = r end
  end
  check("homing bits draw the trail's red circles, not WA's green gas, on the generated record",
    spec and spec.patch.c_homing_sprite == 250 and spec.patch.c_homing_kind == 1
      and spec.patch.cluster_count == 7)
end

print("old woman launcher: launch the Old Woman from a clear point")
do
  new_match()
  local P = 0x10000
  local spec
  for _, r in ipairs(replaced) do
    if r.weapon == "old_woman" then spec = r end
  end
  check("stock Old Woman supplies the animal and Lua handles its projectile",
    spec and spec.copy_from == "old_woman" and type(spec.on_fire) == "function"
      and spec.patch.fire_type == 1 and spec.patch.fire_method == 3)
  local w = worm(17)
  w.x, w.y = 100 * P, 100 * P
  M.solid = function(x) return x <= 91 * P end
  spec.on_fire({ worm = w, x = 86 * P, y = w.y, vx = -12 * P, vy = 0 })
  check("a wall at the muzzle moves the Old Woman into clear space",
    #M.launched == 1 and M.launched[1].weapon == "old_woman"
      and M.launched[1].x >= 94 * P and M.launched[1].fuse == 5000)
  M.solid = nil
  spec.on_fire({ worm = w, x = 114 * P, y = w.y, vx = 12 * P, vy = 0 })
  check("a clear muzzle keeps WA's original launch point",
    #M.launched == 2 and M.launched[2].x == 114 * P)
  -- A thin wall (105-108) between the worm and a clear muzzle beyond it:
  -- the worm can't see the muzzle, so she starts on the worm's side.
  M.solid = function(x) return x >= 105 * P and x < 109 * P end
  M.trace_hit = function(x0, _, x1)
    local wall = 107 * P
    if (x0 - wall) * (x1 - wall) < 0 then return { hit = true, x = wall, y = w.y } end
  end
  spec.on_fire({ worm = w, x = 114 * P, y = w.y, vx = 12 * P, vy = 0 })
  check("a muzzle past a thin wall moves her back to the worm's side",
    #M.launched == 3 and M.launched[3].x < 105 * P and M.launched[3].x > w.x - 40 * P,
    #M.launched == 3 and M.launched[3].x / P or #M.launched)
  M.trace_hit = nil
  M.solid = function() return true end
  spec.on_fire({ worm = w, x = 86 * P, y = w.y, vx = -12 * P, vy = 0 })
  check("with no clear point within 40 pixels she starts at the worm",
    #M.launched == 4 and M.launched[4].x == w.x and M.launched[4].y == w.y)
  M.solid = nil
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
  local was_turn = w.turn
  w.turn = true -- thrown in its turn
  M.missile(m)
  w.turn = was_turn
  check("the thrown Chilli's own banana hidden in flight", m.sprite == 0)
  local b = { id = 611, phase = "pre", weapon = "bazooka", x = 0, y = 0, vx = P, vy = 0, sprite = 48 }
  M.missile(b)
  check("other missiles keep theirs", b.sprite == 48)
  M.message(worm(32), wa.msg.FRAME_FINISH)
  check("launched once", #M.launched == 5)
  -- The blast hurt the thrower, which ends WA's turn: no worm holds the turn
  -- while the five fly, and they are drawn all the same.
  M.turn_start({ worm = w })
  for _, x in ipairs(wa.worms.all()) do x.turn = false end
  M.spawned = {}
  local child = { id = 620, phase = "post", weapon = "super_banana", x = 0, y = 0, vx = P, vy = -P, sprite = 0 }
  M.missile(child)
  check("the five are drawn after the turn ends, for the last turn's worm",
    M.spawned[1] and M.spawned[1].sprite == "sprites/px_hold/chilli_bomb" and M.spawned[1].owner == w)
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

print("helicopter: PX's script on WA's jet pack")
do
  new_match()
  frame()
  local P = 0x10000
  local w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.facing, w.turn = "jet_pack", "prefiring", 100 * P, 50 * P, 0, 0, 1, true
  w.fuel, w.gravity, w.wind, w.body_visible = 30 * P, P, 0, true
  w.keys = { up = false, down = false, left = false, right = false }
  function w:clear_keys() error("Helicopter must leave key consumption to the engine") end
  function w:set_state() error("Helicopter must leave landing state to WA") end
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
  check("the engine owns the keys after the script reads them", w.steered and w.keys.up)
  check("the helicopter replaces the climb-in", climb.dead and M.spawned[#M.spawned].sprite == "sprites/helicopter/flying")
  -- In game, the engine consumes this key after the callback.
  w.keys.up = false
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
  -- WA ends the jet pack on the ground without a scripted state change.
  w.state = "prefiring"
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "jetpacking"
  M.message(w, wa.msg.FRAME_FINISH)
  w.fuel, w.vy, w.vx = 50 * P, 0, 0
  w.state = "standing"
  n = #M.spawned
  M.message(w, wa.msg.FRAME_FINISH)
  check("WA ends the jet pack at rest: its state survives, no explosion", w.state == "standing" and #M.spawned == n
    and w.gravity == P and not w.steered and w.body_visible == true)
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

print("hot air balloon: PX's balloon, flown with WA's parachute physics upside down")
do
  new_match()
  frame()
  local P = 0x10000
  M.gravity, M.wind, M.water, M.solid = 0x4000, 0, nil, nil
  local w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.facing, w.turn = "bungee", "sliding", 100 * P, 50 * P, 0, P, 1, true
  w.gravity, w.body_visible, w.alliance, w.keys = P, true, 1, {}
  for i, o in ipairs(worms) do
    if o ~= w then o.x, o.y = -1000 * P * i, 0 end
  end
  function w:set_state() error("the balloon takes and releases the worm; it sets no state") end
  M.spawned, M.sounds = {}, {}
  M.message(w, wa.msg.FRAME_FINISH)
  check("nothing while it just falls", #M.spawned == 0 and not w.taken)
  -- WA opens the parachute and clears the selection: "none", as seen in WA.
  w.state, w.weapon = "parachuting", "none"
  local y0 = w.y
  M.message(w, wa.msg.FRAME_FINISH)
  check("taken for the flight, the turn running", w.taken and w.taken.turn == "run")
  check("an inflate sound", M.sounds[1] and M.sounds[1]:find("inflate"))
  -- WA's step: gravity (upside down) in, then damped to 0.8.
  check("its first step: the fall turned upward, damped", w.y - y0 == (P - 0x4000) * 0xCCCC // P,
    tostring((w.y - y0) / P))
  local balloon, basket = M.spawned[1], M.spawned[2]
  check("the balloon in the team's colour, the basket below", balloon.sprite == "sprites/balloon/balloon"
    and balloon.tint == 0xFF0096FF and basket.sprite == "sprites/balloon/basket" and w.body_visible == false,
    string.format("%x", balloon.tint or 0))
  check("the balloon 43 above, 6 ahead; the basket's art mirrored facing right",
    balloon.y == w.y - 43 * P and balloon.x == w.x + 6 * P and basket.facing == -1)
  -- It settles at four times gravity upward and four times the wind across.
  M.wind = 0x100
  for _ = 1, 100 do M.message(w, wa.msg.FRAME_FINISH) end
  local x1, y1 = w.x, w.y
  M.message(w, wa.msg.FRAME_FINISH)
  check("rising at four times gravity", math.abs((w.y - y1) + 4 * 0x4000) <= 8, tostring(w.y - y1))
  check("drifting with four times the wind", math.abs((w.x - x1) - 4 * 0x100) <= 8, tostring(w.x - x1))
  -- The arrow keys push it, half of gravity a frame, as WA's parachute:
  -- the new speed is (last + push + wind) damped, and it moves by it.
  local function step_x(keys)
    local before, last = w.x, w.x - x1
    x1, w.keys = w.x, keys
    M.message(w, wa.msg.FRAME_FINISH)
    return w.x - before, last
  end
  local dx, last = step_x({ left = true })
  check("left pushes it left by half of gravity", dx == (last - 0x2000 + 0x100) * 0xCCCC // P,
    dx .. " " .. last)
  dx, last = step_x({ left = true, right = true })
  check("left and right together cancel", dx == (last + 0x100) * 0xCCCC // P, dx .. " " .. last)
  dx, last = step_x({ right = true })
  check("right pushes it right", dx == (last + 0x2000 + 0x100) * 0xCCCC // P, dx .. " " .. last)
  w.keys = {}
  check("weapons fire from the basket", M.message(w, wa.msg.FIRE_WEAPON) ~= "eat" and w.taken)
  -- The jump key pops it: the worm back to WA, falling with its speed.
  check("the jump key pops it", M.message(w, wa.msg.JUMP) == "eat" and M.sounds[#M.sounds]:find("pop")
    and balloon.dead and w.body_visible == true and not w.taken and w.state == "sliding" and w.vy < 0)
  local function up_again()
    w.state, w.weapon = "sliding", "bungee"
    M.message(w, wa.msg.FRAME_FINISH)
    w.state, w.weapon = "parachuting", "none"
    M.message(w, wa.msg.FRAME_FINISH)
    return w.taken
  end
  -- Up again, into land above it: it pops there.
  check("up again", up_again())
  local top = w.y - 5 * P
  M.solid = function(_, y) return y < top end
  for _ = 1, 20 do
    M.message(w, wa.msg.FRAME_FINISH)
    if not w.taken then break end
  end
  check("land: popped, the worm back to WA, not pushed up into it", not w.taken
    and w.state == "sliding" and w.vy >= 0 and M.sounds[#M.sounds]:find("pop"))
  M.solid = nil
  -- WA stands it up against the ceiling: released again, falling.
  w.state, w.vy = "standing", 0
  M.message(w, wa.msg.FRAME_FINISH)
  check("stood up under the ceiling: released again", w.state == "sliding")
  w.state = "standing"
  M.message(w, wa.msg.FRAME_FINISH)
  check("only once", w.state == "standing")
  -- Up again; the engine lets go at the turn's end: it pops.
  check("up again", up_again())
  w.taken = nil
  M.message(w, wa.msg.FRAME_FINISH)
  check("the turn over: popped", M.sounds[#M.sounds]:find("pop") and w.body_visible == true)
  -- Up again, then the next turn begins.
  check("up again", up_again())
  M.turn_start({ worm = worm(32), active = worm(32) })
  check("a turn change pops it", not w.taken and w.body_visible == true)
  -- The Hang-Glider's parachute is not a balloon.
  local n = #M.spawned
  w.state, w.weapon, w.keys = "sliding", "parachute", {}
  M.message(w, wa.msg.FRAME_FINISH)
  w.state = "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  local balloons = 0
  for i = n + 1, #M.spawned do
    if M.spawned[i].sprite == "sprites/balloon/balloon" then balloons = balloons + 1 end
  end
  check("another slot's parachute is left alone", balloons == 0)
  M.message(w, wa.msg.JUMP)
end

print("automatic parachute: only the equipped weapon opens")
do
  new_match()
  frame()
  local P = 0x10000
  M.gravity, M.wind, M.water, M.solid, M.trace_hit = 0x3AE, 0, nil, nil, nil
  local w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.turn =
    "bungee", "sliding", 100 * P, 50 * P, 0, P, true
  M.spawned, M.sounds = {}, {}
  M.message(w, wa.msg.FRAME_FINISH)
  -- WA has replaced the selected slot with stock Parachute while opening.
  w.weapon, w.state = "parachute", "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  check("equipped balloon owns the auto opening despite WA's slot change",
    w.taken and M.spawned[1] and M.spawned[1].sprite == "sprites/balloon/balloon")
  local glider = false
  for _, a in ipairs(M.spawned) do
    if a.sprite == "sprites/hang_glider/glider" then glider = true end
  end
  check("equipped balloon does not start the glider", not glider)
  M.message(w, wa.msg.JUMP)

  new_match()
  frame()
  w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.turn =
    "parachute", "sliding", 100 * P, 50 * P, 0, P, true
  w.keys = {}
  M.spawned = {}
  M.message(w, wa.msg.FRAME_FINISH)
  w.weapon, w.state = "none", "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  check("equipped glider owns its auto opening",
    M.spawned[1] and M.spawned[1].sprite == "sprites/hang_glider/glider" and w.taken)
  M.message(w, wa.msg.JUMP)

  new_match()
  frame()
  w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.turn =
    "shotgun", "sliding", 100 * P, 50 * P, 0, P, true
  M.spawned = {}
  M.message(w, wa.msg.FRAME_FINISH)
  check("another equipped weapon keeps falling", w.state == "sliding" and #M.spawned == 0)
  -- Even an unexpected stock parachute state must not turn into either mod.
  w.weapon, w.state = "none", "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  check("another equipped weapon claims neither parachute replacement", #M.spawned == 0 and not w.taken)

  new_match()
  frame()
  w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.turn =
    "parachute", "sliding", 100 * P, 50 * P, 0, P, true
  M.spawned = {}
  M.message(w, wa.msg.FRAME_FINISH)
  w.weapon = "shotgun"
  M.message(w, wa.msg.FRAME_FINISH)
  w.weapon, w.state = "none", "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  check("putting the glider away removes its automatic claim", #M.spawned == 0 and not w.taken)
end

print("hang-glider: PX's glider, flown by the pack")
do
  new_match()
  frame()
  local P = 0x10000
  M.gravity, M.wind, M.water, M.solid, M.trace_hit = 0x3AE, 0, nil, nil, nil -- a small pull, as WA's is
  for i, o in ipairs(worms) do o.x, o.y = -1000 * P * i, 0 end
  local w = worm(16)
  w.weapon, w.state, w.x, w.y, w.vx, w.vy, w.facing, w.turn = "parachute", "sliding", 100 * P, 50 * P, 3 * P, P, 1, true
  w.body_visible, w.keys = true, {}
  function w:set_state() error("the glider takes and releases the worm; it sets no state") end
  M.spawned, M.sounds = {}, {}
  M.message(w, wa.msg.FRAME_FINISH)
  check("nothing while it just falls", #M.spawned == 0 and w.body_visible == true)
  -- WA opens the parachute and clears the selection: the pack takes over.
  w.state, w.weapon = "parachuting", "none"
  local x0, y0 = w.x, w.y
  M.message(w, wa.msg.FRAME_FINISH)
  local art = M.spawned[1]
  check("opens: taken, the glider sound and art, the body hidden", w.taken and w.taken.turn == "run"
    and M.sounds[1] and M.sounds[1]:find("hangopen")
    and art and art.sprite == "sprites/hang_glider/glider" and w.body_visible == false)
  check("its art faces left, as WA's worms: mirrored facing right", art.facing == -1)
  -- Level, the wing's up side is straight up: a quarter of the fall goes.
  check("the speed carries on into the glide; the wing takes a quarter of the fall",
    math.abs((w.x - x0) - 3 * P) <= 1 and math.abs((w.y - y0) - (1 + 0x3AE * 0.75 / P) * 0.75 * P) <= 1,
    (w.x - x0) .. " " .. (w.y - y0))
  for _ = 1, 30 do M.message(w, wa.msg.FRAME_FINISH) end
  check("and the nose follows the flight path", art.angle ~= 0, tostring(art.angle))
  check("it opens over 25 frames", art.shown == 9, tostring(art.shown))
  check("weapons fire while it glides", M.message(w, wa.msg.FIRE_WEAPON) ~= "eat" and w.taken)
  -- Nose up: the nose angle drops, faster the faster it flies.
  w.keys = { up = true }
  for _ = 1, 10 do M.message(w, wa.msg.FRAME_FINISH) end
  w.keys = {}
  check("up turns the nose up", art.angle and art.angle > 180, tostring(art.angle))
  local function glide_again(vy)
    w.state, w.weapon, w.vx, w.vy = "sliding", "parachute", 3 * P, vy or P
    M.message(w, wa.msg.FRAME_FINISH)
    w.state, w.weapon = "parachuting", "none"
    M.message(w, wa.msg.FRAME_FINISH)
    return w.taken
  end
  -- Into something ahead, no land below: a crash, the worm back to WA with
  -- the glider's speed, and no pack-away.
  local n = #M.spawned
  local wall = w.x + 7 * P
  M.solid = function(x) return x >= wall end
  M.message(w, wa.msg.FRAME_FINISH)
  M.solid = nil
  check("a crash: let go, falling on", not w.taken and w.state == "sliding" and w.vx > 0)
  check("closed: the sound, the art gone, the body back",
    M.sounds[#M.sounds]:find("hangclose") and art.dead and w.body_visible == true)
  w.state = "standing"
  M.message(w, wa.msg.FRAME_FINISH)
  check("and no pack-away; stood up where it hit, released again", #M.spawned == n
    and w.state == "sliding")
  -- Coming down onto land: let go, then begin the pack-away at WA's terrain
  -- contact instead of waiting for its delayed standing state.
  check("gliding again", glide_again())
  local floor = w.y + 13 * P // 2
  M.solid = function(_, y) return y >= floor end
  M.message(w, wa.msg.FRAME_FINISH)
  M.solid = nil
  check("about to land: let go", not w.taken and w.state == "sliding")
  local landing_art = M.spawned[#M.spawned]
  check("gentle landing keeps the wing over the worm until contact",
    landing_art.sprite == "sprites/hang_glider/glider" and not landing_art.dead
    and w.body_visible == false)
  w.state, w.x, w.y = "jump_falling", w.x + P, w.y + P
  M.message(w, wa.msg.FRAME_FINISH)
  check("the wing follows the falling worm without exposing its body",
    landing_art.x == w.x and landing_art.y == w.y and not landing_art.dead
    and w.body_visible == false)
  M.contact(w, { kind = "land" }, { vx = w.vx, vy = w.vy, flags = 0 })
  local pack = M.spawned[#M.spawned]
  check("land contact immediately replaces the wing with pack-away, before WA stands the worm",
    landing_art.dead and pack.sprite == "sprites/hang_glider/pack"
    and w.state == "jump_falling" and w.body_visible == false and pack.facing == -1)
  M.message(w, wa.msg.FRAME_FINISH)
  check("pack-away runs while WA is still in the landing handoff",
    not pack.dead and pack.shown == 0 and w.body_visible == false)
  w.state = "standing"
  for _ = 1, 12 do M.message(w, wa.msg.FRAME_FINISH) end
  check("six frames at 24 a second", pack.shown == 5 and not pack.dead, tostring(pack.shown))
  M.message(w, wa.msg.FRAME_FINISH)
  check("then the worm again", pack.dead and w.body_visible == true)
  -- A movement key interrupts the pack-away even before WA has changed the
  -- worm's landing state to walking.
  check("gliding again", glide_again())
  floor = w.y + 13 * P // 2
  M.solid = function(_, y) return y >= floor end
  M.message(w, wa.msg.FRAME_FINISH)
  M.solid = nil
  M.contact(w, { kind = "land" }, { vx = w.vx, vy = w.vy, flags = 0 })
  local interrupted_pack = M.spawned[#M.spawned]
  w.keys = { left = true }
  M.message(w, wa.msg.FRAME_FINISH)
  check("moving interrupts pack-away and returns to WA's worm immediately",
    interrupted_pack.dead and w.body_visible == true)
  w.keys = {}
  check("gliding again", glide_again())
  floor = w.y + 13 * P // 2
  M.solid = function(_, y) return y >= floor end
  M.message(w, wa.msg.FRAME_FINISH)
  M.solid = nil
  M.contact(w, { kind = "land" }, { vx = w.vx, vy = w.vy, flags = 0 })
  local jump_pack = M.spawned[#M.spawned]
  check("jump interrupts pack-away without eating WA's jump",
    M.message(w, wa.msg.JUMP) ~= "eat" and jump_pack.dead and w.body_visible == true)
  check("gliding again", glide_again())
  floor = w.y + 13 * P // 2
  M.solid = function(_, y) return y >= floor end
  M.message(w, wa.msg.FRAME_FINISH)
  M.solid = nil
  n = #M.spawned
  w.keys = { right = true }
  M.contact(w, { kind = "land" }, { vx = w.vx, vy = w.vy, flags = 0 })
  check("a held movement key skips the pack-away at contact",
    #M.spawned == n and w.body_visible == true)
  w.keys = {}
  -- A fast downward arrival gives WA the full speed. The engine holds the
  -- equipped chute closed until WA has resolved the impact and any damage.
  check("gliding into a hard landing", glide_again(20 * P))
  n = #M.spawned
  floor = w.y + 13 * P // 2
  M.solid = function(_, y) return y >= floor end
  M.message(w, wa.msg.FRAME_FINISH)
  M.solid = nil
  check("hard landing: fall at full speed without auto chute", not w.taken
    and w.state == "sliding" and w.vy >= 8 * P - 1
    and w.release_options and w.release_options.suppress_auto_parachute == true,
    string.format("taken=%s state=%s vy=%s", tostring(w.taken), tostring(w.state), tostring(w.vy)))
  w.state = "standing"
  M.message(w, wa.msg.FRAME_FINISH)
  check("hard landing: no safe pack-away or mid-air unstick",
    #M.spawned == n and w.state == "standing",
    string.format("spawned=%d expected=%d state=%s", #M.spawned, n, tostring(w.state)))
  -- The jump key lets go of it.
  check("gliding again", glide_again())
  check("the jump key: let go", M.message(w, wa.msg.JUMP) == "eat" and not w.taken
    and M.sounds[#M.sounds]:find("hangclose"))
  -- The engine lets go at the turn's end.
  check("gliding again", glide_again())
  w.taken = nil
  M.message(w, wa.msg.FRAME_FINISH)
  check("the turn over: closed", M.sounds[#M.sounds]:find("hangclose") and w.body_visible == true)
  -- The balloon's parachute is not a glider.
  w.state, w.weapon = "sliding", "bungee"
  M.message(w, wa.msg.FRAME_FINISH)
  n = #M.spawned
  w.state = "parachuting"
  M.message(w, wa.msg.FRAME_FINISH)
  local glider = false
  for i = n + 1, #M.spawned do
    if M.spawned[i].sprite == "sprites/hang_glider/glider" then glider = true end
  end
  check("the Hot Air Balloon's parachute is left alone", not glider)
  M.message(w, wa.msg.JUMP)
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
  function w:set_state() error("the Swim Suit takes and releases the worm; it sets no state") end
  function w:clear_keys() error("a taken worm's keys are the engine's to clear") end
  local function frames(n, until_fn)
    for _ = 1, n do
      M.message(w, wa.msg.FRAME_FINISH)
      if until_fn and until_fn() then return end
    end
  end
  -- Into the water, falling fast: a splash, taken by the pack for the swim
  -- with the turn running, the speed capped.
  w.state, w.y, w.vx, w.vy = "sliding", 510 * P, 9 * P, 12 * P
  local x0, y0 = w.x, w.y
  M.message(w, wa.msg.FRAME_FINISH)
  check("splash, taken for the swim, the turn running", M.sounds[#M.sounds] == 57 and w.taken
    and w.taken.turn == "run" and w.state == "sliding")
  local dx, dy = w.x - x0, w.y - y0
  check("the speed capped at 5 (2.5 times the swim speed 2), then eased", dx < 5 * P and dy < 5 * P
    and dx > 4 * P and dy > 4 * P, dx .. " " .. dy)
  check("the swim animation in its place, facing left art mirrored", w.body_visible == false
    and M.spawned[#M.spawned].sprite == "sprites/swim_suit/swim" and M.spawned[#M.spawned].facing == -1)
  -- Swimming left: a push that way, turned.
  x0, w.keys = w.x, { left = true }
  M.message(w, wa.msg.FRAME_FINISH)
  check("left: 0.2 a frame slower, facing left", w.x - x0 == math.floor((5 / 1.05 - 0.2) * P)
    and w.facing == -1, tostring((w.x - x0) / P))
  check("no jumping while it swims", M.message(w, wa.msg.JUMP) == "eat")
  local spent_before = spent
  check("no weapons while it swims", M.message(w, wa.msg.FIRE_WEAPON) == "eat" and spent == spent_before)
  -- Land in the way: it stops there.
  M.solid = function(x) return x >= w.x + 6 * P end
  x0, w.keys = w.x, { right = true }
  M.message(w, wa.msg.FRAME_FINISH)
  check("land stops it", w.x == x0 and w.taken, tostring((w.x - x0) / P))
  M.solid = nil
  -- Still, no key: the float animation, once it has glided to a stop.
  w.keys = {}
  frames(120)
  check("still: floating", M.spawned[#M.spawned].sprite == "sprites/swim_suit/float" and w.taken)
  -- Up out of the water: released as from a jump, the suit still on.
  w.keys = { up = true }
  frames(200, function() return not w.taken end)
  check("out: released above the surface, moving up, the suit still on", w.state == "sliding"
    and w.vy < 0 and w.y < M.water and w.collision_mask == 134342 and w.body_visible == true)
  M.message(w, wa.msg.FRAME_FINISH)
  check("no second splash on the way out", not w.taken)
  -- Back in, then too deep: it gives out and the worm drowns.
  w.y, w.vx, w.vy, w.keys = 510 * P, 0, 0, { down = true }
  frames(200, function() return w.state == "tumbling" end)
  check("too deep: out of control, the water's bit back, drawn as itself", w.state == "tumbling"
    and not w.taken and w.collision_mask == 134342 | 0x400000 and w.body_visible == true)
  -- Fast Walk: swim speed 6 for the turn.
  w.weapon, w.keys = "fast_walk", {}
  M.message(w, wa.msg.FIRE_WEAPON)
  w.weapon, w.state, w.y, w.vx, w.vy = "laser_sight", "sliding", 400 * P, 0, 0
  M.message(w, wa.msg.FIRE_WEAPON)
  x0 = w.x
  w.y, w.vx, w.vy = 510 * P, 20 * P, 0
  M.message(w, wa.msg.FRAME_FINISH)
  check("Fast Walk: capped at 15", w.x - x0 > 14 * P and w.x - x0 <= 15 * P, tostring((w.x - x0) / P))
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
  -- The turn ends with it in the water: the engine lets go, and it drowns.
  w.taken, w.vx, w.vy = nil, 0, 0
  M.message(w, wa.msg.FRAME_FINISH)
  check("the turn over, in the water: out of control, the water's bit back", w.state == "tumbling"
    and w.collision_mask & 0x400000 ~= 0 and w.body_visible == true)
  M.message(w, wa.msg.FRAME_FINISH)
  check("and no longer the pack's", not w.taken)
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
  check("turn start leaves Gravity Control active", M.gravity == math.floor(0x3AE * 2.4))
  M.turn_end({ worm = w, active = w })
  check("turn end restores the match's gravity", M.gravity == 0x3AE)
  -- PX's rule: the turn clock standing still for 10 s puts the gravity back.
  local high = math.floor(0x3AE * 2.4)
  M.digit = 5
  M.message(w, wa.msg.FRAME_FINISH)
  M.digit = nil
  M.message(w, wa.msg.FIRE_WEAPON)
  M.turn_clock = 20000
  for _ = 1, 120 do
    M.message(w, wa.msg.FRAME_FINISH)
  end
  check("a shot's settling (2.4 s, clock still) keeps the gravity", M.gravity == high)
  for i = 1, 600 do
    M.turn_clock = 20000 - i * 20
    M.message(w, wa.msg.FRAME_FINISH)
  end
  check("a running clock keeps it however long", M.gravity == high)
  for _ = 1, 499 do
    M.message(w, wa.msg.FRAME_FINISH)
  end
  check("the clock still for 499 frames keeps it", M.gravity == high)
  M.message(w, wa.msg.FRAME_FINISH)
  check("10 s with the clock still puts the gravity back", M.gravity == 0x3AE, tostring(M.gravity))
  M.turn_end({ worm = w, active = w })
  check("turn end after that leaves the match's gravity", M.gravity == 0x3AE)
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
  function w:set_state() error("the Jump releases the worm; it sets no state") end
  M.spawned, M.sounds = {}, {}
  M.message(w, wa.msg.FIRE_WEAPON)
  M.message(w, wa.msg.FRAME_FINISH)
  check("charging: the worm keeps its aim posture", #M.spawned == 0 and w.body_visible)
  spec.on_fire({ worm = w, x = w.x, y = w.y, vx = 3 * P, vy = -5 * P })
  check("fired: the shot's speed, airborne", w.vx == 3 * P and w.vy == -5 * P and w.state == "sliding")
  check("the team's Jump line: team 2's bank", M.sounds[#M.sounds] == 150 + 54, tostring(M.sounds[#M.sounds]))
end

print("laser gun: PX's 5 s beam in place of the uzi's bullet")
do
  new_match()
  frame()
  local P = 0x10000
  local spec
  for _, r in ipairs(replaced) do if r.weapon == "uzi" then spec = r end end
  local shooter, target = worm(16), worm(32)
  for _, o in ipairs(worms) do o.turn = false end
  shooter.turn, shooter.weapon, shooter.aim, shooter.facing = true, "uzi", 0.5, 1
  shooter.x, shooter.y = 100 * P, 100 * P
  target.x, target.y = 160 * P, 100 * P
  local drum = { kind = "oil", id = 1, x = 200 * P, y = 100 * P, taken = 0 }
  function drum:hit(damage) self.taken = self.taken + damage end
  M.oil = { drum }
  M.trace_hit = { x = 300 * P, y = 100 * P }
  M.spawned, M.sounds, M.digs = {}, {}, {}
  spec.on_fire({ worm = shooter, x = shooter.x, y = shooter.y, vx = 0, vy = 0 })
  spec.on_fire({ worm = shooter, x = shooter.x, y = shooter.y, vx = 0, vy = 0 })
  check("one beam per worm, with its start and loop sounds", #M.spawned == 1
    and M.sounds[1] == "sounds/laser_gun/laser_start.wav" and M.sounds[2] == "sounds/laser_gun/laser_loop.wav")
  local beam = M.spawned[1]
  local function tick(n) for _ = 1, n do if not beam.dead then beam.on(beam) end end end
  tick(1)
  check("the worm is held firing: 0 of 1 shots", shooter.shots_fired == 0 and shooter.shots_to_fire == 1)
  check("the first trace: 2 to the worm, 4 to the drum, a 4 px cut where it hits land",
    target.hp == 98 and drum.taken == 4 and M.digs[1] and M.digs[1].x == 300 * P and M.digs[1].radius == 4,
    tostring(target.hp) .. " " .. tostring(drum.taken))
  tick(39)
  check("every fourth frame: 2 until 10 taken, then 1", target.hp == 85, tostring(target.hp))
  M.quads, M.ribbons = {}, {}
  M.draw()
  local strip = M.ribbons[1]
  check("a red strip from 24 px out to where it hits, PX's width", strip
    and strip.sprite == "sprites/laser_gun/laser_beam.png" and (strip.points[1].color & 0xFFFFFF) == 0xFF0000
    and strip.points[2].x == 300 * P and strip.points[1].width <= 16 and strip.points[1].width >= 8)
  tick(210)
  check("no more than 45 from one beam", target.hp == 55, tostring(target.hp))
  check("after 250 frames it stops and lets WA end the shot", shooter.shots_fired == shooter.shots_to_fire
    and M.sounds[#M.sounds] == "sounds/laser_gun/laser_end.wav")
  tick(200)
  check("its sparks gone, the beam is released", beam.dead)
  M.spawned = {}
  spec.on_fire({ worm = shooter, x = shooter.x, y = shooter.y, vx = 0, vy = 0 })
  check("the next shot starts a new beam", #M.spawned == 1)
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

print("Super Tele: frozen click, 50-frame delay, three cuts and cavern ceiling")
do
  local P = 0x10000
  new_match()
  local spec
  for _, r in ipairs(replaced) do if r.weapon == "teleport" then spec = r end end
  local w = worm(16)
  w.x, w.y, w.hp = 40 * P, 70 * P, 100
  local target_x, target_y = 190 * P + 1234, 100 * P + 2345
  spec.on_click({ worm = w, x = target_x, y = target_y })
  local marker = M.spawned[#M.spawned]
  check("target marker stays at the frozen click position",
    marker.sprite == "markerr" and marker.x == target_x and marker.y == target_y and not marker.dead)
  check("click confirms target with PX sound and flags",
    w.state ~= "teleporting" and M.sounds[1] == 68 and M.sound_flags[1] == 0)
  M.message(w, wa.msg.FRAME_FINISH)
  check("the next frame enters WA's teleport pose and plays PX's start sound",
    w.state == "teleporting" and M.sounds[2] == 67 and M.sound_flags[2] == 0)
  for _ = 1, 49 do M.message(w, wa.msg.FRAME_FINISH) end
  check("worm and marker remain in place for 49 frames after starting",
    w.x == 40 * P and w.y == 70 * P and not M.digs and not marker.dead)
  M.message(w, wa.msg.FRAME_FINISH)
  check("frame 50 arrives at the saved target and removes its marker",
    w.x == target_x and w.y == target_y and marker.dead)
  local cuts = M.digs or {}
  check("arrival cuts three overlapping holes at and above the destination",
    #cuts == 3 and cuts[1].x == target_x and cuts[1].y == target_y
      and cuts[2].y == target_y - 10 * P and cuts[3].y == target_y - 22 * P
      and cuts[1].radius == 12 and cuts[2].radius == 12 and cuts[3].radius == 12)
  for _ = 1, 5 do M.message(w, wa.msg.FRAME_FINISH) end
  check("arrival runs once", #M.digs == 3)

  new_match({ cavern = true })
  spec = nil
  for _, r in ipairs(replaced) do if r.weapon == "teleport" then spec = r end end
  w = worm(16)
  spec.on_click({ worm = w, x = 50 * P, y = 2 * P })
  for _ = 1, 51 do M.message(w, wa.msg.FRAME_FINISH) end
  check("cavern clicks stay at least 19 pixels below the ceiling", w.y == 19 * P)

  new_match()
  spec = nil
  for _, r in ipairs(replaced) do if r.weapon == "teleport" then spec = r end end
  w = worm(16)
  w.x, w.y = 40 * P, 70 * P
  spec.on_click({ worm = w, x = 200 * P, y = 150 * P })
  marker = M.spawned[#M.spawned]
  w.hp = 0
  for _ = 1, 50 do M.message(w, wa.msg.FRAME_FINISH) end
  check("a dead worm is never moved or carved in and its marker is removed",
    w.x == 40 * P and w.y == 70 * P and not M.digs and marker.dead)
end

print("lightning strike: warning, hit, grave identity and copied hand")
do
  local P = 0x10000
  new_match()
  local click
  for _, spec in ipairs(replaced) do
    if spec.weapon == "napalm_strike" then click = spec.on_click; break end
  end
  local jumper = worm(16)
  jumper.turn, jumper.weapon = true, "napalm_strike"
  jumper.state = "prefiring"
  function jumper:set_state() error("the engine ends a click-only fire's prefire, not the pack") end
  click({ worm=jumper, x=100*P, y=100*P })
  check("click leaves ending WA's prefiring pose to the engine", jumper.state == "prefiring")

  -- The strike comes from where WA's arrow points (the sign of ev.vx), not
  -- from the worm's facing. With no land the beam ends 300 pixels along it,
  -- which is where its effect sits: left of the click when it comes from
  -- the left.
  new_match()
  local facing_right = worm(16)
  facing_right.facing = 1
  click({ worm = facing_right, x = 100 * P, y = 100 * P, vx = -P })
  local from_right = M.spawned[#M.spawned]
  facing_right.facing = -1
  click({ worm = facing_right, x = 100 * P, y = 100 * P, vx = P })
  local from_left = M.spawned[#M.spawned]
  check("the arrow, not the worm's facing, sets the side it strikes from",
    from_right.x > 100 * P and from_left.x < 100 * P, (from_right.x / P) .. "," .. (from_left.x / P))

  new_match()
  local by_slot = {}
  for _, spec in ipairs(replaced) do by_slot[spec.weapon] = spec end
  local owner, target = worm(16), worm(17)
  owner.x, owner.y = 100 * P, 100 * P
  target.x, target.y = 100 * P, 100 * P
  for _, w in ipairs(worms) do
    if w ~= owner and w ~= target then w.x, w.y = 1000 * P, 1000 * P end
  end
  by_slot.napalm_strike.on_click({ worm=owner, x=100*P, y=100*P })
  local effect = M.spawned[#M.spawned]
  for _ = 1, 149 do effect.on(effect) end
  check("150 frame warning leaves health alone", target.hp == 100)
  effect.on(effect)
  M.draw()
  check("active strike emits a terrain-occluded GPU ribbon",
    #M.ribbons > 0 and M.ribbons[1].depth == 0x00190000)
  for _ = 1, 15 do effect.on(effect) end
  check("beam stays active for 16 frames", target.hp == 100)
  effect.on(effect)
  check("final hit heals the living worm by 25", target.hp == 125)
  M.quads = {}
  M.draw()
  local puffs = 0
  for _, q in ipairs(M.quads) do
    if q.sprite == "sprites/lightning/cloud.png" and q.blend == "alpha" and (q.color & 0xFFFFFF) == 0x2D283C then
      puffs = puffs + 1
    end
  end
  check("PX's cloud: dark puffs built up over the warning, drawn behind the terrain", puffs > 60, tostring(puffs))
  for _ = 1, 60 do effect.on(effect) end
  check("after the 60 frame tail the effect waits for its last puff", not effect.dead)
  for _ = 1, 140 do effect.on(effect) end
  check("the last puff gone, the effect is released", effect.dead)

  -- The grave is matched to the dead worm before the strike; revival returns
  -- the same stable ID and restores the copied inventory to that worm.
  new_match()
  by_slot = {}
  for _, spec in ipairs(replaced) do by_slot[spec.weapon] = spec end
  owner, target = worm(16), worm(17)
  owner.x, owner.y = 100 * P, 100 * P
  target.x, target.y = 140 * P, 100 * P
  for _, w in ipairs(worms) do
    if w ~= owner and w ~= target then w.x, w.y = 1000 * P, 1000 * P end
  end
  turn(16)
  frame()
  local original = hand(17)
  kill(17)
  remove(17)
  local grave = { id=701, kind="grave", worm_id=17, x=140*P, y=100*P }
  function grave:revive(id, hp)
    assert(id == 17 and hp == 10)
    local revived = setmetatable({ id=id, kind="worm", team=1, alliance=0, ammo_group=0,
      hp=hp, x=self.x, y=self.y-5*P, facing=1 }, Worm)
    worms[#worms+1] = revived
    M.graves = {}
    return revived
  end
  M.graves = { grave }
  by_slot.napalm_strike.on_click({ worm=owner, x=140*P, y=100*P })
  effect = M.spawned[#M.spawned]
  for _ = 1, 166 do effect.on(effect) end
  local revived = worm(17)
  check("linked grave revives its own worm at 10 HP", revived and revived.hp == 10)
  turn(17)
  local have = {}
  for _, name in ipairs(original) do have[name] = true end
  local restored = true
  for name in pairs(have) do if ammo[0][name] ~= 1 then restored = false end end
  check("the original Highlander hand is restored", restored)

  new_match()
  by_slot = {}
  for _, spec in ipairs(replaced) do by_slot[spec.weapon] = spec end
  owner = worm(16)
  owner.x, owner.y = 100*P, 100*P
  for _, w in ipairs(worms) do if w ~= owner then w.x, w.y = 1000*P, 1000*P end end
  local mine = { id=702, kind="mine", x=100*P, y=100*P, fuse=2500 }
  function mine:arm(fuse) self.armed = fuse end
  M.mines = {mine}
  local before_rng = rng
  by_slot.napalm_strike.on_click({ worm=owner, x=100*P, y=100*P })
  effect = M.spawned[#M.spawned]
  for _ = 1, 166 do effect.on(effect) end
  check("a fixed-fuse mine keeps its timer without an RNG draw",
    mine.armed == 2500 and rng == before_rng)
  mine.fuse, mine.armed = -1, nil
  by_slot.napalm_strike.on_click({ worm=owner, x=100*P, y=100*P })
  effect = M.spawned[#M.spawned]
  for _ = 1, 166 do effect.on(effect) end
  check("a random-fuse mine draws one 1–5 s fuse in simulation",
    mine.armed >= 1000 and mine.armed <= 5000 and rng ~= before_rng)
end

print("electric grenade: seek, delayed zap, and target kinds")
do
  local P = 0x10000
  local function setup()
    new_match()
    local spec
    for _, r in ipairs(replaced) do if r.weapon == "earthquake" then spec = r end end
    local owner = worm(16)
    for _, w in ipairs(worms) do w.x, w.y = 1000*P, 1000*P end
    owner.x, owner.y = 0, 0
    return spec, owner
  end
  local function tick(n)
    local a = M.spawned[#M.spawned]
    for _ = 1, n do if not a.dead then a.on(a) end end
  end
  -- Dozens of live arcs, drawn: the draw refills its tables rather than
  -- making garbage for every glow, so Lua's GC does not run inside it.
  do
    local spec, owner = setup()
    for i = 1, 40 do spec.on_explode({ worm = owner, x = i * 40 * P, y = 0 }) end
    for _ = 1, 12 do
      for _, a in ipairs(M.spawned) do if not a.dead then a.on(a) end end
    end
    local quad, ribbon = wa.draw.quad, wa.draw.ribbon
    local quads, ribbons = 0, 0
    wa.draw.quad = function() quads = quads + 1 end
    wa.draw.ribbon = function() ribbons = ribbons + 1 end
    M.draw()
    quads, ribbons = 0, 0
    collectgarbage("stop")
    local before = collectgarbage("count")
    M.draw()
    local kb = collectgarbage("count") - before
    collectgarbage("restart")
    wa.draw.quad, wa.draw.ribbon = quad, ribbon
    check("40 arcs drawn without new tables per glow", ribbons == 40 and quads > 400 and kb < 4,
      string.format("%d ribbons, %d quads, %.1f KB", ribbons, quads, kb))
  end
  local spec, owner = setup()
  check("a stock grenade for the worm's throw sheet, PX's hold over it",
    spec.sprite == "grenade" and spec.worm_sprites and spec.worm_sprites.weaponlnk == "sprites/px_hold/aim"
    and spec.params.gpu_prefix == "sprites/px_hold/")
  -- In flight: the stock grenade hidden, PX's grenade drawn in its place.
  M.spawned = {}
  owner.turn = true
  local m = { id = 501, phase = "pre", weapon = "earthquake", x = 10*P, y = 20*P, vx = P, vy = 0, sprite = 50 }
  M.missile(m)
  m.phase = "post"
  M.missile(m)
  check("thrown: WA's sprite hidden, PX's grenade follows it", m.sprite == 0
    and M.spawned[1] and M.spawned[1].sprite == "sprites/px_hold/electric_grenade.png")
  -- Its sprite's owner when no worm holds the turn: the last turn's worm;
  -- if that one died since (WA frees a dead worm, its handle dangles), a
  -- living worm, never the dead one, so PX's grenade is still drawn (WA's
  -- own sprite is the stock grenade, which the Sticky Bomb redraws).
  do
    local before = M.spawned
    owner.turn = false
    M.turn_start({ worm = owner })
    local listed = wa.worms.all
    wa.worms.all = function()
      local alive = {}
      for _, w in ipairs(listed()) do if w ~= owner then alive[#alive + 1] = w end end
      return alive
    end
    M.spawned = {}
    local late = { id = 502, phase = "post", weapon = "earthquake", x = 10*P, y = 20*P, vx = P, vy = 0, sprite = 0 }
    late.phase = "pre"
    late.sprite = 50
    M.missile(late)
    late.phase = "post"
    M.missile(late)
    check("a grenade flying after the last turn's worm died is drawn for a living worm,"
      .. " WA's own sprite hidden", #M.spawned == 1 and M.spawned[1].owner ~= owner
      and M.spawned[1].owner ~= nil and late.sprite == 0)
    wa.worms.all = listed
    M.spawned = {}
    local later = { id = 503, phase = "post", weapon = "earthquake", x = 10*P, y = 20*P, vx = P, vy = 0, sprite = 0 }
    M.missile(later)
    check("while that worm lives, it owns the sprite", M.spawned[1] and M.spawned[1].owner == owner)
    owner.turn = true
    M.spawned = before
  end
  -- It spins as a grenade (its record's WAT_Rotation), not faces its flight:
  -- flying right at 4 px a frame, 0.5 * 4 * 0.15 = 0.3 rad a frame.
  m.vx, m.vy = 4*P, 0
  local before = M.spawned[1].angle
  M.missile(m)
  local turned = (M.spawned[1].angle - before) % 360
  check("thrown: it spins with its speed, as PX's grenade", math.abs(turned - math.deg(0.3)) < 1e-6,
    tostring(turned))
  owner.turn = false
  local target = worm(17)
  target.x, target.y = 5*P, 0
  spec.on_explode({ worm=owner, x=0, y=0 })
  tick(1)
  function target:set_state() error("a tazed worm is taken, not set to a state") end
  function target:clear_keys() error("a tazed worm's keys are the engine's to consume") end
  check("near worm is held in tazed pose", target.taken and target.taken.turn == "freeze"
    and target.body_visible == false)
  check("a tazed worm cannot start a shot", M.message(target, wa.msg.FIRE_WEAPON) == "eat")
  -- The current, drawn: a glow at every point of the strip, and PX's
  -- widths (9 at the thickest, a half width).
  M.quads, M.ribbons = {}, {}
  M.draw()
  local glows = 0
  for _, q in ipairs(M.quads) do if q.sprite == "sprites/lightning/glow.png" then glows = glows + 1 end end
  local strip = M.ribbons[1]
  check("the current glows at every point, PX's width at its ends",
    strip and glows >= #strip.points and math.abs(strip.points[1].width - 2 * 9 * 0.1) < 1e-9,
    tostring(glows) .. " glows")
  tick(23)
  check("zap waits 24 frames", target.hp == 100)
  tick(1)
  check("zap deals 24 and releases movement", target.hp == 76 and target.taken == nil
    and target.state == "sliding" and target.body_visible == true)
  check("released, it may fire again", M.message(target, wa.msg.FIRE_WEAPON) ~= "eat")
  spec, owner = setup()
  local first, second = worm(17), worm(32)
  first.x, first.y = 5*P, 0
  second.x, second.y = 14*P, 0
  spec.on_explode({ worm=owner, x=0, y=0 })
  tick(50)
  check("arc chains to a second unvisited worm", first.hp == 76 and second.hp == 76)
  -- The thrower: as PX's, the arc never zaps the worm that fired the
  -- grenade, whichever worm the explosion names.
  spec, owner = setup()
  owner.weapon = "earthquake"
  M.message(owner, wa.msg.FIRE_WEAPON)
  first = worm(17)
  first.x, first.y = 5*P, 0
  spec.on_explode({ worm=worm(32), x=0, y=0 })
  tick(50)
  check("the arc spares the worm that threw the grenade", owner.hp == 100 and first.hp == 76,
    tostring(owner.hp) .. " " .. tostring(first.hp))
  -- The trail: every point stays from the grenade on, links included.
  spec, owner = setup()
  first = worm(17)
  first.x, first.y = 60*P, 0
  spec.on_explode({ worm=owner, x=0, y=0 })
  local function drawn_points()
    M.quads, M.ribbons = {}, {}
    M.draw()
    local r = M.ribbons[#M.ribbons]
    return r and #r.points or 0
  end
  local before, after = drawn_points(), nil
  for _ = 1, 30 do
    tick(1)
    if first.taken then after = drawn_points(); break end
    before = drawn_points()
  end
  check("linking to a worm keeps the trail it came along", after and before >= 3 and after == before + 1,
    tostring(before) .. " -> " .. tostring(after))
  spec, owner = setup()
  local mine = { id=800, kind="mine", x=5*P, y=0 }
  function mine:arm(fuse) self.fuse = fuse end
  M.mines = {mine}
  spec.on_explode({ worm=owner, x=0, y=0 })
  tick(25)
  check("chained mine arms on a 400 ms fuse", mine.fuse == 400)
  spec, owner = setup()
  local crate = { id=801, kind="crate", x=5*P, y=0 }
  function crate:hit(damage) self.damage = damage end
  M.crates = {crate}
  spec.on_explode({ worm=owner, x=0, y=0 })
  tick(25)
  check("object zap passes 12 damage", crate.damage == 12)
  -- Two arcs hold one worm and the first zap kills it. The engine's worm
  -- lists leave dead worms out; the second zap must release it anyway, or
  -- the engine holds a dead worm, which never comes to rest, and the turn
  -- the hold froze never ends.
  spec, owner = setup()
  local held = worm(17)
  held.x, held.y, held.hp = 5*P, 0, 20
  local listed = wa.worms.all
  wa.worms.all = function()
    local alive = {}
    for _, w in ipairs(listed()) do if w.hp > 0 then alive[#alive + 1] = w end end
    return alive
  end
  M.spawned = {}
  spec.on_explode({ worm=owner, x=0, y=0 })
  spec.on_explode({ worm=owner, x=0, y=0 })
  for _ = 1, 30 do
    for _, a in ipairs(M.spawned) do if not a.dead then a.on(a) end end
  end
  wa.worms.all = listed
  check("a worm killed while two arcs hold it is still released", held.hp == 0 and held.taken == nil
    and held.body_visible == true)
  spec, owner = setup()
  M.trace_hit = { x=0, y=-5*P, nx=1, ny=0, tx=0, ty=1, starts_solid=false }
  spec.on_explode({ worm=owner, x=0, y=0 })
  tick(1)
  check("terrain trace can redirect the arc", #M.spawned > 0 and not M.spawned[#M.spawned].dead)
  -- An explosion WA reports without a worm: the turn's worm owns the arc's
  -- driver, not the exploding grenade (which lends no collision helper).
  spec, owner = setup()
  for _, w in ipairs(worms) do w.turn = false end
  owner.turn = true
  M.spawned = {}
  spec.on_explode({ x=0, y=0 })
  check("an explosion without a worm: the turn's worm owns the arc", M.spawned[1] and M.spawned[1].owner == owner)
end

print("Javelin: ordered thrusts and terrain stamps")
do
  new_match()
  local spec
  for _, r in ipairs(replaced) do if r.weapon == "prod" then spec = r end end
  check("prod uses Javelin's record and GPU art", spec.wep == "weps/prod.wep"
    and spec.params.gpu_prefix == "sprites/javelin/" and type(spec.on_explode) == "function")
  local P = 0x10000
  local owner = worms[1]
  owner.x, owner.y, owner.turn = 1000 * P, 1000 * P, true
  local nearby = {}
  wa.world.electrical_nearby = function(x, y, r, graves)
    assert(r == 29 and not graves)
    return nearby
  end
  local id = 0
  local function impact(vx, vy)
    id = id + 1
    M.missile({ weapon = "prod", id = id, phase = "pre", vx = vx, vy = vy })
    -- WA's explosion reports the missile's owner, which is not a worm.
    spec.on_explode({ x = 100 * P, y = 100 * P, missile = id, worm = { owner_object = true } })
  end
  local a, b = worms[2], worms[3]
  a.x, a.y, b.x, b.y = 119 * P, 119 * P, 100 * P, 100 * P
  nearby = { a, b }
  impact(8 * P, -4 * P)
  check("first target wins, including square corners outside a 20px circle", a.hp == 80 and b.hp == 100)
  check("worm thrust uses quarter incoming velocity", a.vx == 2 * P and a.vy == -P)
  check("hitting an object never stamps", M.stamps == nil)
  a.x, a.y = 120 * P, 100 * P
  nearby = { a }
  impact(P, 0)
  check("20px boundary is excluded", a.hp == 80 and #M.stamps == 1)
  nearby = {}
  owner.x, owner.y = 124 * P, 124 * P
  impact(-7, 7)
  check("active worm has PX's 25px fallback and truncates towards zero", owner.hp == 80
    and owner.vx == -1 and owner.vy == 1 and #M.stamps == 1)
  owner.x, owner.y = 125 * P, 100 * P
  impact(0, 0)
  check("25px fallback boundary is excluded; zero speed points up", owner.hp == 80 and M.stamps[2].frame == 0)
  owner.x, owner.y = 1000 * P, 1000 * P
  for _, kind in ipairs({"mine", "crate", "oil"}) do
    local o = { kind = kind, x = 100 * P, y = 100 * P }
    function o:hit(damage, vx, vy, mode) self.hit_args = { damage, vx, vy, mode } end
    nearby = { o }
    impact(-8 * P, 4 * P)
    check(kind .. " receives 20 projectile damage and thrust", o.hit_args[1] == 20
      and o.hit_args[2] == -4 * P and o.hit_args[3] == 2 * P and o.hit_args[4] == "projectile"
      and o.vx == -2 * P and o.vy == P and #M.stamps == 2)
  end
  nearby = {}
  local cases = { {0,-1,0}, {1,0,8}, {0,1,16}, {-1,0,24}, {1,-1,3}, {1,1,11},
    {-1,1,19}, {-1,-1,27}, {100,-1,7}, {1,100,15}, {-100,1,23}, {-1,-100,31} }
  local good = true
  for _, c in ipairs(cases) do
    impact(c[1] * P, c[2] * P)
    local stamp = M.stamps[#M.stamps]
    good = good and stamp.frame == c[3] and stamp.sprite == "sprites/javelin/stamp"
      and stamp.x == 100 * P and stamp.y == 100 * P
  end
  check("cardinals, ratio bins and clamps choose PX's centered 60px stamp", good)
  local last = M.stamps[#M.stamps]
  check("the half in the land fades into it", last.buried and last.buried.soften == 3
    and last.buried.blend == "mix")
  check("sticking plays the registered impact sound on the turn's worm, never the missile's owner",
    M.sounds[#M.sounds] == "sounds/javelin_impact.wav" and M.sound_targets[#M.sound_targets] == owner)
  local n = #M.stamps
  M.draw()
  check("drawing never writes terrain", #M.stamps == n)
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

-- ------------------------------------------------------------ baseline

-- A value as text: tables with their keys sorted, functions as <function>.
local function serialize(v, seen)
  local t = type(v)
  if t == "string" then
    return string.format("%q", v)
  elseif t == "number" then
    return math.type(v) == "integer" and tostring(v) or string.format("%.17g", v)
  elseif t ~= "table" then
    return t == "function" and "<function>" or tostring(v)
  end
  seen = seen or {}
  if seen[v] then
    return "<cycle>"
  end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and type(a) ~= "table" then
      return a < b
    end
    return type(a) < type(b)
  end)
  local parts = {}
  for _, k in ipairs(keys) do
    local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or "[" .. serialize(k, seen) .. "]"
    parts[#parts + 1] = key .. " = " .. serialize(v[k], seen)
  end
  seen[v] = nil
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function baseline()
  local out = {}
  local function add(line)
    out[#out + 1] = line
  end

  new_match()
  add("# claims, in wa.weapons.replace order")
  for _, spec in ipairs(replaced) do
    add(spec.weapon .. " " .. serialize(spec))
  end

  add("")
  add("# hooks registered, by event")
  local hooks = {
    worm_message = M.handlers, turn_start = M.turn_starts, turn_end = M.turn_ends,
    missile_frame = M.missile_handlers, draw = M.draws, contact = M.contacts, hurt = M.hurt_handlers,
  }
  for _, name in ipairs({
    "contact", "death", "draw", "hud", "hurt", "missile_frame",
    "turn_end", "turn_start", "worm_message",
  }) do
    local n = hooks[name] and #hooks[name] or (M[name] and 1 or 0)
    add(("%s %d"):format(name, n))
  end

  add("")
  add("# globals the pack defines")
  local globals = {}
  for k in pairs(_G) do
    if not PRISTINE[k] and k ~= "wa" then
      globals[#globals + 1] = tostring(k)
    end
  end
  table.sort(globals)
  for _, k in ipairs(globals) do
    add(k)
  end

  -- What each hand position can be dealt: 200 worms, open and cavern.
  for _, map in ipairs({ "open", "cavern" }) do
    add("")
    add("# hands dealt at match start, " .. map .. " map (4 worms, fixed RNG)")
    new_match({ cavern = map == "cavern" })
    frame()
    for _, id in ipairs({ 16, 17, 32, 33 }) do
      add(("%d %s"):format(id, table.concat(hand(id) or {}, ", ")))
    end
    add("")
    add("# what each hand position can be dealt, " .. map .. " map (200 worms)")
    new_match({ cavern = map == "cavern", per_team = 100, seed = 4242 })
    frame()
    local seen = {}
    for _, w in ipairs(worms) do
      for i, name in ipairs(hand(w.id) or {}) do
        seen[i] = seen[i] or {}
        seen[i][name] = true
      end
    end
    for i = 1, #seen do
      add(("%d %s"):format(i, table.concat(wa.sorted(seen[i]), ", ")))
    end
  end
  return table.concat(out, "\n") .. "\n"
end

local BASELINE = "mods/examples/highlander/baseline.txt"
print("worm_message: every handler names its messages")
do
  new_match()
  local open = 0
  for i = 1, #M.handlers do
    if not M.handler_msgs[i] then open = open + 1 end
  end
  -- One handler without a filter makes the engine call into Lua for every
  -- message every worm gets, several a frame each.
  check("no handler takes every message", open == 0, open .. " of " .. #M.handlers)
end

print("baseline: the pack's claims, hooks, globals and deals")
do
  local now = baseline()
  if arg and arg[1] == "--baseline" then
    local f = assert(io.open(BASELINE, "w"))
    f:write(now)
    f:close()
    print("  wrote " .. BASELINE)
  else
    -- A host that runs this suite from elsewhere (lua-host's test, from the
    -- crate's folder) hands the file's text in as HIGHLANDER_BASELINE.
    local was = HIGHLANDER_BASELINE
    if was == nil then
      local f = io.open(BASELINE, "r")
      was = f and f:read("a")
      if f then f:close() end
    end
    -- A Windows checkout may hand the file back with CRLF line endings.
    was = was and was:gsub("\r\n", "\n")
    local differs
    if was and was ~= now then
      local a, b = {}, {}
      for line in was:gmatch("[^\n]*") do a[#a + 1] = line end
      for line in now:gmatch("[^\n]*") do b[#b + 1] = line end
      for i = 1, math.max(#a, #b) do
        if a[i] ~= b[i] then
          differs = ("line %d:\n    was: %s\n    now: %s"):format(i, tostring(a[i]), tostring(b[i]))
          break
        end
      end
    end
    check("matches baseline.txt (rewrite with --baseline when intended)", was == now,
      was == nil and "no baseline.txt" or differs)
  end
end

print("")
if fails == 0 then
  print("ALL PASS")
else
  print(("%d FAILED"):format(fails))
  os.exit(1)
end
