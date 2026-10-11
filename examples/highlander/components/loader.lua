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
  ["hl.double_bazooka"] = "bazooka",
  ["hl.igniter"] = "homing_missile",
  ["hl.s_m_a_r_t_bomb"] = "mortar",
  ["hl.blaster_worm"] = "homing_pigeon",
  ["hl.burning_sheep_launcher"] = "sheep_launcher",
  ["hl.sticky_bomb"] = "grenade",
  ["hl.windy_cluster"] = "cluster_bomb",
  ["hl.super_gravedigger"] = "banana_bomb",
  ["hl.thumper_nade"] = "battle_axe",
  ["hl.electric_grenade"] = "earthquake",
  ["hl.real_shotgun"] = "shotgun",
  ["hl.sniper_rifle"] = "handgun",
  ["hl.laser_gun"] = "uzi",
  ["hl.burst_rifle"] = "minigun",
  ["hl.shadow_bolt"] = "longbow",
  ["hl.fire_jump"] = "fire_punch",
  ["hl.sentry_laser"] = "dragon_ball",
  ["hl.sentry_gun"] = "kamikaze",
  ["hl.kamikaze_rocket"] = "suicide_bomber",
  ["hl.javelin"] = "prod",
  ["hl.dynamite"] = "dynamite",
  ["hl.nuke_rocket"] = "mine",
  ["hl.pogo_sheep"] = "sheep",
  ["hl.ghost_sheep"] = "aqua_sheep",
  ["hl.gravler"] = "mole_bomb",
  ["hl.mortar_strike"] = "air_strike",
  ["hl.lightning_strike"] = "napalm_strike",
  ["hl.pigeon_strike"] = "mail_strike",
  ["hl.gravler_strike"] = "mole_squadron",
  ["hl.blowtorch"] = "blow_torch",
  ["hl.super_drill"] = "pneumatic_drill",
  ["hl.baseball_bat"] = "girder",
  ["hl.electromagnet"] = "baseball_bat",
  ["hl.3_girder_pack"] = "girder_pack",
  ["hl.jump"] = "ninja_rope",
  ["hl.hot_air_balloon"] = "bungee",
  ["hl.hang_glider"] = "parachute",
  ["hl.super_tele"] = "teleport",
  ["hl.portal_gun"] = "scales_of_justice",
  ["hl.chilli_bomb"] = "super_banana",
  ["hl.hellish_hand_grenade"] = "holy_grenade",
  ["hl.flame_thrower"] = "flame_thrower",
  ["hl.ferret"] = "salvation_army",
  ["hl.banana_express"] = "mb_bomb",
  ["hl.valyrian_fire"] = "petrol_bomb",
  ["hl.remote_roller"] = "skunk",
  ["hl.priceless_ming_vase"] = "ming_vase",
  ["hl.bowling_ball_strike"] = "sheep_strike",
  ["hl.thumper_nade_strike"] = "carpet_bomb",
  ["hl.cow_launcher"] = "mad_cow",
  ["hl.old_woman_launcher"] = "old_woman",
  ["hl.crate_strike"] = "donkey",
  ["hl.reinforcement"] = "nuclear_test",
  ["hl.ice_arrow"] = "armageddon",
  ["hl.skip_go_surrender"] = "skip_go",
  ["hl.wind_changer"] = "surrender",
  ["hl.weapon_crate"] = "freeze",
  ["hl.cluster_bomb"] = "magic_bullet",
  ["hl.helicopter"] = "jet_pack",
  ["hl.gravity_control"] = "low_gravity",
  ["hl.fast_walk"] = "fast_walk",
  ["hl.swim_suit"] = "laser_sight",
  ["hl.teleport"] = "invisibility",
  ["hl.skunk"] = "damage_x2",
  ["hl.crate_spy"] = "crate_spy",
  ["hl.mole_bomb"] = "double_turn_time",
  ["hl.crate_shower"] = "crate_shower",
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
