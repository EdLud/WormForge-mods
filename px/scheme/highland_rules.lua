-- Highlander gameplay: deal hands, refresh turn ammo, and transfer loot on death.
--
-- A port of Project X's `scheme_hl_0rang3` (Highlander 0rang3 1.1).
-- The source (`highlander.txt`) does all of this with four calls:
-- SetWeaponEx(team, weapon, 1) to grant and SetWeaponEx(team, weapon, 0) to
-- take away. `worm:ammo(name, { set = n })` is the same absolute write. It has
-- to be absolute: a stock scheme gives some of these weapons infinite ammo,
-- and adding to infinite leaves it infinite.
--
-- Where this differs from the source, on purpose:
--
--   * No turn-end removal. PX removes a worm's weapons at M_TURNEND and again,
--     through CurW, at the next M_TURNBEGIN. The second alone is enough, so
--     this listens for one message instead of two.
--
--     START_TURN (0x34) reaches only the worm whose turn it is: WA's handler
--     marks the receiver turn-active and calls TeamArena::SetActiveWorm on it
--     unconditionally (OpenWA `msg_start_turn`), which would be nonsense sent
--     to every worm. So the worm it arrives on IS the active worm.
--
--   * Every pooled slot is zeroed for every team at each turn start, not
--     just the previous worm's. PX relied on its scheme having those slots at
--     zero. Here the scheme can say anything, so the pack enforces it itself.
--     What a team took from crates is put back after the zeroing (below).
--
--   * PX's GiveWeapons also sets the Hot Air Balloon to 3 and the Wind
--     Changer to 1 each turn. The Highlander scheme gives them as weapon data
--     (profiles/Highlander.toml), so this file alone doesn't.
--
-- Lockstep: dealing, turn_start and death are all dispatched from WA's own
-- simulation messages, and every random choice is wa.random(). Two peers, or
-- a peer and a replay, deal the same hands and make the same grants. Nothing
-- here reads local input or the clock.
local shared = require("lib/shared")
local POOLS = shared.POOLS
local arsenal = shared.arsenal
local dead_hands = shared.dead_hands
local dealt = shared.dealt
local describe = shared.describe
local revived_by_lightning = shared.revived_by_lightning

-- ----------------------------------------------------------------- rules

-- One from each pool, dealt to a worm on the first message it receives -- as
-- PX does on each worm's first M_FRAME. Dealing everyone at once on the very
-- first message would assume every worm already exists by then; this makes no
-- such assumption. Worms receive messages in WA's own entity order, which is
-- the same on every peer, so the draws still come out of WA's RNG in the same
-- sequence everywhere.
local function deal(worm)
  local cave = wa.world.cavern()
  for _, name in ipairs({ "offensive", "second", "movement" }) do
    local pool = POOLS[cave and "cave_" .. name or name]
    -- A profile may leave a pool empty: nothing to deal from it.
    if #pool > 0 then
      arsenal:deal(worm, pool, 1)
    end
  end
  dealt[worm.id] = true
  wa.log(string.format(
    "highlander: worm %d dealt %s (%s map)",
    worm.id, describe(arsenal:list(worm)), cave and "cavern" or "open"
  ))
end

-- ---------------------------------------------------------------- crates

-- A pooled weapon from a crate is the team's, not the worm's: any of its
-- worms may use it, on that turn or a later one, until it is used, and it
-- is never refilled. WA puts a crate's ammo in the collector's ammo row at
-- once (one row per alliance, which WA shares), so it is usable the turn it
-- is collected; each zeroing of the pooled slots would take it back, so the
-- row's crate stock is laid over the hand again after it.
--
-- The hand's use goes first. A row given hand h (0 or 1) and crate stock s
-- that has r left has used h + s - r, the crate's being those past h, so
-- the crate stock left is s - max(0, s - r) = min(s, r): read before every
-- write that would lose it.
local POOLED = shared.POOLED
local is_pooled = {}
for _, id in ipairs(POOLED) do is_pooled[id] = true end
local crate_stock = {} -- [ammo_group][weapon] = copies

-- One live worm per ammo row, in WA's worm order.
local function rows()
  local out, seen = {}, {}
  for _, live in ipairs(wa.worms.all()) do
    if not seen[live.ammo_group] then
      seen[live.ammo_group] = true
      out[#out + 1] = live
    end
  end
  return out
end

-- The ammo row a crate's collector draws on. A homing missile may collect
-- for a worm that has since died: then any worm of its team.
local function row_of(worm_id)
  local team_row
  for _, live in ipairs(wa.worms.all()) do
    if live.id == worm_id then return live.ammo_group end
    if team_row == nil and live.team == worm_id // 16 then team_row = live.ammo_group end
  end
  return team_row
end

-- Walks POOLED, not pairs(): the same order on every peer. `only`, a set
-- of weapon ids, limits it to those.
local function count_crate_uses(live_rows, only)
  for _, live in ipairs(live_rows) do
    local stock = crate_stock[live.ammo_group]
    if stock then
      for _, name in ipairs(POOLED) do
        local s = stock[name]
        if s and (not only or only[name]) then
          local left = live:ammo(name)
          if left >= 0 and left < s then stock[name] = left > 0 and left or nil end
        end
      end
    end
  end
end

local function restore_crate_stock(live_rows, only)
  for _, live in ipairs(live_rows) do
    local stock = crate_stock[live.ammo_group]
    if stock then
      for _, name in ipairs(POOLED) do
        local s = stock[name]
        if s and (not only or only[name]) then
          local have = live:ammo(name)
          if have >= 0 then live:ammo(name, { set = have + s }) end
        end
      end
    end
  end
end

wa.on.weapon_grant(function(event)
  if event.source ~= "crate" then return end
  local row
  for _, item in ipairs(event.items) do
    if is_pooled[item.weapon] then
      row = row or row_of(event.worm_id)
      if row == nil then return end
      local stock = crate_stock[row] or {}
      crate_stock[row] = stock
      stock[item.weapon] = (stock[item.weapon] or 0) + item.amount
      wa.log(string.format(
        "highlander: worm %d's team keeps %d %s from a crate (%d in its stock)",
        event.worm_id, item.amount, item.weapon, stock[item.weapon]
      ))
    end
  end
end)

-- -------------------------------------------------------------- the turn

-- The hand, one use of each, for the turn, over the team's crate stock.
-- PX's GiveWeapons (the Hot Air Balloons and the Wind Changer) is weapon
-- data in the Highlander profile: the engine gives it.
local function start_turn(worm)
  local live = rows()
  count_crate_uses(live)
  arsenal:apply(worm, { clear = true, each = 1 })
  restore_crate_stock(live)
end

local function on_death(event)
  local victim = event.victim
  local active = event.active
  revived_by_lightning[victim.id] = nil
  local mine = arsenal:list(victim)
  dead_hands[victim.id] = mine

  if active and active.id == victim.id then
    -- Died on its own turn: nothing to hand on, just take its weapons away.
    local live = rows()
    count_crate_uses(live)
    arsenal:clear(victim)
    arsenal:apply(victim, { clear = true, each = 1 })
    restore_crate_stock(live)
    wa.log(string.format("highlander: worm %d died on its own turn", victim.id))
    return
  end

  -- Otherwise the worm whose turn it is gets everything -- whoever or
  -- whatever did the killing, friend or foe, exactly as in PX.
  if not active or active.hp <= 0 then
    return
  end
  arsenal:transfer(victim, active, {
    weapons = "all", mode = "move", x = victim.x, y = victim.y,
  })
  -- Usable at once, this turn, not from the stealer's next turn, over
  -- what its team has of them from crates.
  local stolen = {}
  for _, name in ipairs(mine) do stolen[name] = true end
  count_crate_uses({ active }, stolen)
  arsenal:apply(active, { weapons = mine, each = 1 })
  restore_crate_stock({ active }, stolen)
  wa.log(string.format(
    "highlander: worm %d took %s from worm %d",
    active.id, describe(mine), victim.id
  ))
end

wa.on.worm_message(function(worm, msg)
  if not dealt[worm.id] then
    deal(worm)
  end
end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.START_TURN } })

-- A worm that comes in a dead worm's place (the Reinforcement) is a new
-- worm: a fresh hand, dealt at its first message as every worm's is, not
-- what the dead one held or left behind.
shared.fresh_hand = function(worm)
  arsenal:clear(worm)
  dealt[worm.id] = nil
  dead_hands[worm.id] = nil
  revived_by_lightning[worm.id] = nil
end

wa.on.turn_start(function(event)
  start_turn(event.worm)
end)

wa.on.death(on_death)

