-- Set up the selected weapons and their dependencies once, in the established hook order.

local shared = require("lib/shared")
local index = require("weapons/index")
local loader = {}
local loaded, placed_ids = false, nil
local also = {}
local want = {} -- path -> true: set up, or to be

local ORDER = {
  "lib/holds",
  "weapons/old_woman_launcher",
  "weapons/super_drill",
  "weapons/fire_jump",
  "lib/anim",
  "weapons/sniper_rifle",
  "lib/missile_sprites",
  "weapons/double_bazooka",
  "weapons/chilli_bomb",
  "weapons/homing_fire_cluster",
  "weapons/fire_cluster_bomb",
  "weapons/digging_cluster_bomb",
  "weapons/homing_digger",
  "weapons/homing_cluster_bomb",
  "weapons/ninja_bomb",
  "weapons/nuke_rocket",
  "weapons/helicopter",
  "weapons/hot_air_balloon",
  "weapons/hang_glider",
  "weapons/wings",
  "weapons/swim_suit",
  "weapons/underwater_bomb",
  "weapons/wind_changer",
  "weapons/gravity_control",
  "weapons/sacrifice",
  "weapons/parkour",
  "weapons/anti_fall_damage",
  "weapons/platform",
  "lib/poison_cloud",
  "weapons/toxic_grenade",
  "weapons/poison_grenade",
  "weapons/bulldozer",
  "weapons/trampoline",
  "weapons/mine_launcher",
  "weapons/gravity_gun",
  "weapons/personal_invisibility",
  "weapons/small_worm",
  "lib/turn_controls",
  "weapons/jump",
  "weapons/thrown_dynamite",
  "weapons/tnt",
  "weapons/laser_gun",
  "weapons/super_tele",
  "weapons/electric_grenade",
  "weapons/barrel_launcher",
  "weapons/lightning_strike",
  "weapons/tazer",
  "weapons/skip_go_surrender",
  "weapons/drilling_crew",
  "lib/electrical",
  "weapons/javelin",
  "weapons/girder_launcher",
  "weapons/ice_arrow",
  "weapons/valyrian_fire",
  "weapons/reinforcement",
  "lib/bowling_balls",
  "weapons/bowling_ball",
  "weapons/bowling_ball_single",
  "weapons/ferret",
  "lib/magnet",
  "weapons/electromagnet",
  "weapons/fan",
  "weapons/magnetic_missile",
  "weapons/crate_strike",
  "weapons/submarine_attack",
  "weapons/sentry_gun",
  "weapons/sentry_laser",
  "weapons/petrol_turret",
  "weapons/flame_turret",
  "weapons/mine_turret",
  "weapons/auto_ballista",
  "weapons/kamikaze_rocket",
  "weapons/weapon_crate",
  "weapons/random_trap_crate",
  "weapons/mine_reveal",
  "weapons/portal_gun",
}

local function need(path)
  if want[path] then return end
  want[path] = true
  local module = require(path)
  if type(module) == "table" then
    for _, dependency in ipairs(module.requires or {}) do need(dependency) end
  end
end

-- Each module in ORDER that `want` has and `done` hasn't, set up.
local function set_up(done)
  for _, path in ipairs(ORDER) do
    if want[path] and not done[path] then
      local module = require(path)
      if type(module) == "table" and module.setup then module.setup() end
    end
  end
end

-- A module a component sets up as well; one asked for once the others are set up
-- (two add-ons that both install before the weapons) is set up then.
function loader.also(path)
  if not loaded then
    also[#also + 1] = path
    return
  end
  local done = {}
  for p in pairs(want) do done[p] = true end
  need(path)
  set_up(done)
end

function loader.place(ctx)
  if placed_ids then return placed_ids end
  local ids = {}
  for id in pairs(ctx.weapons) do ids[#ids + 1] = id end
  table.sort(ids)
  placed_ids = ids
  return ids
end

function loader.load(ids)
  if loaded then return end
  loaded = true
  require("lib/weapon")
  shared.fires = {}
  shared.missile_sprites = {}
  for id, path in pairs(index) do
    local definition = require(path)
    if definition.missile_sprite then shared.missile_sprites[id] = definition.missile_sprite end
  end
  for _, path in ipairs({ "lib/holds", "weapons/old_woman_launcher", "lib/anim", "lib/missile_sprites" }) do
    want[path] = true
  end
  for _, id in ipairs(ids) do
    if index[id] then need(index[id]) end
  end
  for _, path in ipairs(also) do need(path) end
  set_up({})
end

function loader.install(ctx)
  loader.load(loader.place(ctx))
  local path = index[ctx.id]
  if not path then error(ctx.id .. ": not a Highlander weapon") end
  local weapon = require(path)
  local declaration = weapon.definition
  if type(declaration) == "function" then declaration = declaration() end
  local spec = require("lib/weapon").merge(declaration, {})
  if weapon.configure then weapon.configure(ctx, spec) end
  require("lib/weapon").claim(ctx.id, spec)
end
return loader
