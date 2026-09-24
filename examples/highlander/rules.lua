-- Highlander, stock weapons only.
--
-- A port of the rules in Project X's `scheme_hl_0rang3` (Highlander 0rang3
-- 1.1), without its custom weapons. Every worm is dealt one weapon from each
-- of three pools at the start of the match. Only the worm whose turn it is
-- may use its weapons, one shot of each per turn. Kill a worm and you take
-- everything it carried.
--
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
--
--   * Wind Changer (x1) and Hot Air Balloon (x3) are PX weapons with no stock
--     equivalent, so nothing is granted in their place.
--
--   * The cavern rule bans strikes by NAME. PX did it by cutting the random
--     range short (RandomInt(0,20) instead of (0,28)), which only works
--     because its list happened to keep the strikes at the end.
--
-- Lockstep: dealing, turn_start and death are all dispatched from WA's own
-- simulation messages, and every random choice is wa.random(). Two peers, or
-- a peer and a replay, deal the same hands and make the same grants. Nothing
-- here reads local input or the clock.

-- ----------------------------------------------------------------- pools

-- Movement: exactly the seven the design names.
local MOVEMENT = {
  "ninja_rope", "girder", "girder_pack", "jet_pack", "low_gravity",
  "fast_walk", "parachute",
}

-- Second weapon: the F4 row, plus what is left of F7 once the girders have
-- gone to movement.
local SECOND = {
  "fire_punch", "dragon_ball", "kamikaze", "suicide_bomber", "prod",
  "blow_torch", "pneumatic_drill", "baseball_bat",
}

-- Offensive: every remaining weapon that does damage, super weapons included.
-- The non-attacks -- bungee, teleport, scales, select worm, freeze, the
-- utilities, skip go and surrender -- are not in any pool. Highlander never
-- touches them, so their ammo is whatever the scheme says.
local OFFENSIVE = {
  -- F1-F3
  "bazooka", "homing_missile", "mortar", "homing_pigeon", "sheep_launcher",
  "grenade", "cluster_bomb", "banana_bomb", "battle_axe", "earthquake",
  "shotgun", "handgun", "uzi", "minigun", "longbow",
  -- F5-F6
  "dynamite", "mine", "sheep", "super_sheep", "aqua_sheep", "mole_bomb",
  "air_strike", "napalm_strike", "mail_strike", "mine_strike", "mole_squadron",
  -- F9-F11
  "super_banana", "holy_grenade", "flame_thrower", "salvation_army", "mb_bomb",
  "petrol_bomb", "skunk", "ming_vase", "sheep_strike", "carpet_bomb",
  "mad_cow", "old_woman", "donkey", "nuclear_test", "armageddon",
  -- F12
  "magic_bullet",
}

-- Everything that arrives from the sky. PX keeps strikes out of caverns, where
-- they would hit the roof.
local CAVE_BANNED = {
  air_strike = true, napalm_strike = true, mail_strike = true,
  mine_strike = true, mole_squadron = true, sheep_strike = true,
  carpet_bomb = true, donkey = true, armageddon = true,
}

-- Every slot this pack owns, in a fixed order. Zeroing walks this list, so it
-- must not depend on pairs() order: Lua's string hashing is seeded per
-- process, and a different order on each peer is a different sequence of
-- writes.
local POOLED = {}
for _, pool in ipairs({ OFFENSIVE, SECOND, MOVEMENT }) do
  for _, name in ipairs(pool) do
    POOLED[#POOLED + 1] = name
  end
end

-- ----------------------------------------------------------------- state

-- The engine store is keyed by stable worm id (team * 16 + index), never by
-- entity address. It is virtual: WA's physical ammo is still alliance-shared
-- and is materialized from one worm's inventory at turn start.
local arsenal = wa.inventory.create({ id = "arsenal", slots = POOLED })
local dealt = {}

local function describe(list)
  if not list or #list == 0 then
    return "(nothing)"
  end
  return table.concat(list, ", ")
end

-- ----------------------------------------------------------------- rules

local function offensive_pool()
  if not wa.world.cavern() then
    return OFFENSIVE
  end
  local pool = {}
  for _, name in ipairs(OFFENSIVE) do
    if not CAVE_BANNED[name] then
      pool[#pool + 1] = name
    end
  end
  return pool
end

-- One from each pool, dealt to a worm on the first message it receives -- as
-- PX does on each worm's first M_FRAME. Dealing everyone at once on the very
-- first message would assume every worm already exists by then; this makes no
-- such assumption. Worms receive messages in WA's own entity order, which is
-- the same on every peer, so the draws still come out of WA's RNG in the same
-- sequence everywhere.
local function deal(worm)
  local cave = wa.world.cavern()
  arsenal:deal(worm, offensive_pool(), 1)
  arsenal:deal(worm, SECOND, 1)
  arsenal:deal(worm, MOVEMENT, 1)
  dealt[worm.id] = true
  wa.log(string.format(
    "highlander: worm %d dealt %s (%s map)",
    worm.id, describe(arsenal:list(worm)), cave and "cavern" or "open"
  ))
end

local function start_turn(worm)
  arsenal:apply(worm, { clear = true, each = 1 })
end

local function on_death(event)
  local victim = event.victim
  local active = event.active
  local mine = arsenal:list(victim)

  if active and active.id == victim.id then
    -- Died on its own turn: nothing to hand on, just take its weapons away.
    arsenal:clear(victim)
    arsenal:apply(victim, { clear = true, each = 1 })
    wa.log(string.format("highlander: worm %d died on its own turn", victim.id))
    return
  end

  -- Otherwise the worm whose turn it is gets everything -- whoever or
  -- whatever did the killing, friend or foe, exactly as in PX.
  if not active or active.hp <= 0 then
    return
  end
  arsenal:transfer(victim, active, { weapons = "all", mode = "move" })
  -- Usable at once, this turn, not from the stealer's next turn.
  arsenal:apply(active, { weapons = mine, each = 1 })
  wa.log(string.format(
    "highlander: worm %d took %s from worm %d",
    active.id, describe(mine), victim.id
  ))
end

wa.on.worm_message(function(worm, msg)
  if not dealt[worm.id] then
    deal(worm)
  end
end)

wa.on.turn_start(function(event)
  start_turn(event.worm)
end)

wa.on.death(on_death)
