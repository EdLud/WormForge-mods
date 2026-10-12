-- Highlander as components: which modules a match's placed weapons need, and
-- loading them once, in rules.lua's order (the order the pack's hooks were
-- tested in).
local shared = require("lib/shared")

-- rules.lua's order, less the scheme's own modules (components/highlander.lua
-- loads those).
local ORDER = {
  "lib/holds", "weapons/catalog", "weapons/wep_data", "weapons/claims",
  "weapons/super_drill", "weapons/fire_jump", "lib/anim", "weapons/sniper_rifle",
  "lib/missile_sprites", "weapons/double_bazooka", "weapons/chilli_bomb",
  "weapons/nuke_rocket", "weapons/helicopter", "weapons/hot_air_balloon",
  "weapons/hang_glider", "weapons/swim_suit", "weapons/wind_gravity",
  "weapons/jump", "weapons/laser_gun", "weapons/super_tele", "weapons/electrical",
  "weapons/javelin", "weapons/ice_arrow", "weapons/valyrian_fire",
  "weapons/reinforcement", "weapons/bowling_ball", "weapons/ferret",
  "weapons/electromagnet", "weapons/crate_strike", "weapons/sentry_gun",
  "weapons/sentry_laser", "weapons/kamikaze_rocket", "weapons/weapon_crate",
  "weapons/portal_gun",
}

-- What every placed weapon needs: its claim, art and the helpers most
-- sections read when they load.
local BASE = {
  "lib/holds", "weapons/catalog", "weapons/wep_data", "weapons/claims",
  "lib/anim", "lib/missile_sprites",
}

-- Home slot -> the module with the weapon's own code. A weapon missing here
-- is its claim alone (a PX record on a stock weapon).
local MODULE = {
  pneumatic_drill = "weapons/super_drill",
  fire_punch = "weapons/fire_jump",
  handgun = "weapons/sniper_rifle",
  bazooka = "weapons/double_bazooka",
  super_banana = "weapons/chilli_bomb",
  mine = "weapons/nuke_rocket",
  jet_pack = "weapons/helicopter",
  bungee = "weapons/hot_air_balloon",
  parachute = "weapons/hang_glider",
  laser_sight = "weapons/swim_suit",
  low_gravity = "weapons/wind_gravity",
  surrender = "weapons/wind_gravity",
  ninja_rope = "weapons/jump",
  uzi = "weapons/laser_gun",
  teleport = "weapons/super_tele",
  earthquake = "weapons/electrical",
  napalm_strike = "weapons/electrical",
  prod = "weapons/javelin",
  armageddon = "weapons/ice_arrow",
  petrol_bomb = "weapons/valyrian_fire",
  nuclear_test = "weapons/reinforcement",
  sheep_strike = "weapons/bowling_ball",
  salvation_army = "weapons/ferret",
  baseball_bat = "weapons/electromagnet",
  donkey = "weapons/crate_strike",
  kamikaze = "weapons/sentry_gun",
  dragon_ball = "weapons/sentry_laser",
  suicide_bomber = "weapons/kamikaze_rocket",
  freeze = "weapons/weapon_crate",
  scales_of_justice = "weapons/portal_gun",
}

-- Module -> modules whose helpers it reads as it loads. Their hooks act only
-- on what their own weapon made, or on the slots Highlander's weapons sit on
-- (shared.slot, shared.owns).
-- What one weapon only calls into another (bowling balls, portals) is looked
-- up when it is called, so it needs nothing here.
local NEEDS = {
  ["weapons/fire_jump"] = { "weapons/super_drill" },
  ["weapons/hot_air_balloon"] = { "weapons/helicopter" },
  ["weapons/hang_glider"] = { "weapons/helicopter", "weapons/sniper_rifle" },
  ["weapons/swim_suit"] = { "weapons/helicopter", "weapons/sniper_rifle" },
  ["weapons/wind_gravity"] = { "weapons/helicopter" },
  ["weapons/javelin"] = { "weapons/helicopter" },
  ["weapons/electrical"] = { "weapons/sniper_rifle" },
}

-- Component id -> its weapon's home slot, the slot the code names it by
-- (mod.toml's default_position).
local HOME = {
  ["px.double_bazooka"] = "bazooka",
  ["px.igniter"] = "homing_missile",
  ["px.s_m_a_r_t_bomb"] = "mortar",
  ["px.blaster_worm"] = "homing_pigeon",
  ["px.burning_sheep_launcher"] = "sheep_launcher",
  ["px.sticky_bomb"] = "grenade",
  ["px.windy_cluster"] = "cluster_bomb",
  ["px.super_gravedigger"] = "banana_bomb",
  ["px.thumper_nade"] = "battle_axe",
  ["px.electric_grenade"] = "earthquake",
  ["px.real_shotgun"] = "shotgun",
  ["px.sniper_rifle"] = "handgun",
  ["px.laser_gun"] = "uzi",
  ["px.burst_rifle"] = "minigun",
  ["px.shadow_bolt"] = "longbow",
  ["px.fire_jump"] = "fire_punch",
  ["px.sentry_laser"] = "dragon_ball",
  ["px.sentry_gun"] = "kamikaze",
  ["px.kamikaze_rocket"] = "suicide_bomber",
  ["px.javelin"] = "prod",
  ["px.dynamite"] = "dynamite",
  ["px.nuke_rocket"] = "mine",
  ["px.pogo_sheep"] = "sheep",
  ["px.ghost_sheep"] = "aqua_sheep",
  ["px.gravler"] = "mole_bomb",
  ["px.mortar_strike"] = "air_strike",
  ["px.lightning_strike"] = "napalm_strike",
  ["px.pigeon_strike"] = "mail_strike",
  ["px.gravler_strike"] = "mole_squadron",
  ["px.blowtorch"] = "blow_torch",
  ["px.super_drill"] = "pneumatic_drill",
  ["px.baseball_bat"] = "girder",
  ["px.electromagnet"] = "baseball_bat",
  ["px.3_girder_pack"] = "girder_pack",
  ["px.jump"] = "ninja_rope",
  ["px.hot_air_balloon"] = "bungee",
  ["px.hang_glider"] = "parachute",
  ["px.super_tele"] = "teleport",
  ["px.portal_gun"] = "scales_of_justice",
  ["px.chilli_bomb"] = "super_banana",
  ["px.hellish_hand_grenade"] = "holy_grenade",
  ["px.ferret"] = "salvation_army",
  ["px.banana_express"] = "mb_bomb",
  ["px.valyrian_fire"] = "petrol_bomb",
  ["px.remote_roller"] = "skunk",
  ["px.priceless_ming_vase"] = "ming_vase",
  ["px.bowling_ball_strike"] = "sheep_strike",
  ["px.thumper_nade_strike"] = "carpet_bomb",
  ["px.cow_launcher"] = "mad_cow",
  ["px.old_woman_launcher"] = "old_woman",
  ["px.crate_strike"] = "donkey",
  ["px.reinforcement"] = "nuclear_test",
  ["px.ice_arrow"] = "armageddon",
  ["px.skip_go_surrender"] = "skip_go",
  ["px.wind_changer"] = "surrender",
  ["px.weapon_crate"] = "freeze",
  ["px.cluster_bomb"] = "magic_bullet",
  ["px.helicopter"] = "jet_pack",
  ["px.gravity_control"] = "low_gravity",
  ["px.swim_suit"] = "laser_sight",
  ["px.skunk"] = "damage_x2",
  ["px.mole_bomb"] = "double_turn_time",
}

local loader = {}
local loaded, placed_homes = false, nil

-- Where this match's Highlander weapons sit: home slot -> the slot the
-- profile placed it on (shared.place). The scheme installs first and calls
-- this too, so its pools deal the weapons where they are.
function loader.place(ctx)
  if placed_homes then
    return placed_homes
  end
  local map, homes = {}, {}
  for id, w in pairs(ctx.weapons) do
    local home = HOME[id]
    if home then
      map[home] = w.stock_slot
      homes[#homes + 1] = home
    end
  end
  -- WA's own weapon stands for the Highlander weapon of its name when the
  -- scheme places the stock one (PX's Flame Thrower is WA's): the pools
  -- deal it and the code finds it there. It loads no module.
  local highlander = {}
  for _, home in pairs(HOME) do
    highlander[home] = true
  end
  for id, w in pairs(ctx.weapons) do
    local name = id:match("^stock%.(.+)$")
    if name and not highlander[name] then
      map[name] = w.stock_slot
    end
  end
  -- pairs() order differs between machines; the set it builds does not.
  table.sort(homes)
  shared.place(map)
  placed_homes = homes
  return homes
end

-- The modules every placed weapon needs, once, in rules.lua's order.
function loader.load(homes)
  if loaded then
    return
  end
  loaded = true
  local want = {}
  local function need(module)
    if want[module] then
      return
    end
    want[module] = true
    for _, m in ipairs(NEEDS[module] or {}) do
      need(m)
    end
  end
  for _, m in ipairs(BASE) do
    need(m)
  end
  for _, home in ipairs(homes) do
    if MODULE[home] then
      need(MODULE[home])
    end
  end
  for _, m in ipairs(ORDER) do
    if want[m] then
      require(m)
    end
  end
end

-- A weapon component's install: where everything sits and the modules for
-- the whole loadout, once; then this weapon's claim of its slot.
function loader.install(ctx)
  loader.load(loader.place(ctx))
  local home = HOME[ctx.id]
  if not (home and shared.claim(home)) then
    error(ctx.id .. ": not a Highlander weapon")
  end
end

return loader
