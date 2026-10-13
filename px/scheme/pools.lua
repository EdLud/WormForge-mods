-- Highlander: the weapon pools. Each worm is dealt one weapon from each.
--
-- Under the hl.rules add-on the pools are each placed weapon's settings
-- ("Highlander pool", "Dealt on cavern maps"), which components/highlander.lua
-- reads into shared.pools before this loads; a PX weapon suggests its PX pool
-- (mod.toml). Without them -- rules.lua, the pack in one piece -- the pools
-- are PX's own lists below.
local shared = require("lib/shared")

-- ----------------------------------------------------------------- pools

-- Offensive: PX's `Weapons`, 29 entries.
local OFFENSIVE = {
  "bazooka",          -- Double Bazooka
  "homing_missile",   -- Igniter
  "mortar",           -- S.M.A.R.T Bomb
  "homing_pigeon",    -- Blaster Worm
  "sheep_launcher",   -- Burning Sheep Launcher
  "grenade",          -- Sticky Bomb
  "cluster_bomb",     -- Windy Cluster
  "banana_bomb",      -- Super Gravedigger
  "battle_axe",       -- Thumper Nade
  "earthquake",       -- Electric Grenade
  "dynamite",         -- Dynamite
  "mine",             -- Nuke Rocket
  "sheep",            -- Pogo Sheep
  "aqua_sheep",       -- Ghost Sheep
  "super_banana",     -- Chilli Bomb
  "holy_grenade",     -- Hellish Hand-Grenade
  "petrol_bomb",      -- Valyrian Fire
  "skunk",            -- Remote Roller
  "ming_vase",        -- Priceless Ming Vase
  "mad_cow",          -- Cow Launcher
  "old_woman",        -- Old Woman Launcher
  -- Not dealt on cavern maps:
  "salvation_army",   -- Ferret
  "air_strike",       -- Mortar Strike
  "mail_strike",      -- Pigeon Strike
  "mine_strike",      -- Submarine Attack
  "mole_squadron",    -- Gravler Strike
  "mb_bomb",          -- Banana Express
  "sheep_strike",     -- Bowling Ball Strike
  "carpet_bomb",      -- Thumper Nade Strike
}

-- Second weapon: PX's `NotWeapons`, 19 entries.
local SECOND = {
  "fire_punch",         -- Fire Jump
  "dragon_ball",        -- Sentry Laser
  "kamikaze",           -- Sentry Gun
  "prod",               -- Javelin
  "girder",             -- Baseball Bat
  "baseball_bat",       -- Electromagnet
  "shotgun",            -- Real Shotgun
  "handgun",            -- Sniper Rifle
  "uzi",                -- Laser Gun
  "minigun",            -- Burst Rifle
  "longbow",            -- Shadow-Bolt
  "blow_torch",         -- BlowTorch
  "pneumatic_drill",    -- Super Drill
  "scales_of_justice",  -- Portal Gun
  "armageddon",         -- Ice Arrow
  "flame_thrower",      -- Flame Thrower
  -- Not dealt on cavern maps:
  "nuclear_test",       -- Reinforcement
  "donkey",             -- Crate Strike
  "napalm_strike",      -- Lightning Strike
}

-- Movement: PX's `MoveWeapons`, 7 entries, all dealt on every map.
local MOVEMENT = {
  "girder_pack",   -- 3 Girder Pack
  "ninja_rope",    -- Jump
  "parachute",     -- Hang-Glider
  "teleport",      -- Super Tele
  "jet_pack",      -- Helicopter
  "low_gravity",   -- Gravity Control
  "laser_sight",   -- Swim Suit
}

-- On cavern maps PX draws RandomInt(0,20) and RandomInt(0,15) instead of the
-- whole lists: the first 21 offensive and first 16 second weapons. What that
-- leaves out is what comes from the sky, plus the Ferret.
local CAVE_OFFENSIVE = 21
local CAVE_SECOND = 16

-- The slots Highlander never pools -- Kamikaze Rocket, Gravler, Hot Air
-- Balloon, Skip Go/Surrender, Wind Changer, Muahaha 3, Weapon Crate, Cluster
-- Bomb, Fast Walk, Teleport, Skunk, Crate Spy, Mole Bomb, Crate Shower -- keep
-- whatever ammo the profile gives them.

-- PX's lists name each weapon by its home slot. Dealt is where each sits
-- this match (shared.slot), and a weapon the profile doesn't place is not
-- dealt; the cavern cut-offs count the placed weapons among PX's first ones.
local function placed(pool, first)
  local all, cave = {}, {}
  for i, home in ipairs(pool) do
    local slot = shared.slot(home)
    if slot then
      all[#all + 1] = slot
      if not first or i <= first then cave[#cave + 1] = slot end
    end
  end
  return all, cave
end

local pools = shared.pools
if not pools then
  pools = {}
  pools.offensive, pools.cave_offensive = placed(OFFENSIVE, CAVE_OFFENSIVE)
  pools.second, pools.cave_second = placed(SECOND, CAVE_SECOND)
  pools.movement, pools.cave_movement = placed(MOVEMENT)
end

-- Every pooled slot, in a fixed order. Zeroing walks this list, so it must
-- not depend on pairs() order: Lua's string hashing is seeded per process,
-- and a different order on each peer is a different sequence of writes.
local POOLED, seen = {}, {}
for _, name in ipairs({ "offensive", "second", "movement" }) do
  for _, slot in ipairs(pools[name]) do
    if not seen[slot] then
      seen[slot] = true
      POOLED[#POOLED + 1] = slot
    end
  end
end

shared.POOLS = pools
shared.POOLED = POOLED
