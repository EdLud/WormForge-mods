-- Highlander: the scheme's weapon pools. Split from rules.lua by tools/split_highlander.py.
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
-- whatever ammo the scheme gives them. The Highlander scheme's own data gives
-- the Hot Air Balloon, the Wind Changer and the Weapon Crate
-- (components/highlander.lua).

-- The pools above name each weapon by its home slot. Dealt is where each
-- sits this match (shared.slot), and a weapon the scheme doesn't place is not
-- dealt; the cavern cut-offs count the placed weapons among PX's first ones.
local function placed(pool, first)
  local out, kept = {}, 0
  for i, home in ipairs(pool) do
    local slot = shared.slot(home)
    if slot then
      out[#out + 1] = slot
      if first and i <= first then kept = kept + 1 end
    end
  end
  return out, kept
end
OFFENSIVE, CAVE_OFFENSIVE = placed(OFFENSIVE, CAVE_OFFENSIVE)
SECOND, CAVE_SECOND = placed(SECOND, CAVE_SECOND)
MOVEMENT = placed(MOVEMENT)

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

shared.CAVE_OFFENSIVE = CAVE_OFFENSIVE
shared.CAVE_SECOND = CAVE_SECOND
shared.MOVEMENT = MOVEMENT
shared.OFFENSIVE = OFFENSIVE
shared.POOLED = POOLED
shared.SECOND = SECOND
