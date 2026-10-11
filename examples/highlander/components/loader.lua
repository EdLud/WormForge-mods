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

-- Slot -> the module with the weapon's own code. A weapon missing here is
-- its claim alone (a PX record on a stock weapon).
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
-- on what their own weapon made, or on slots Highlander owns (shared.owns).
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

local loader = {}
local loaded = false

-- `placed`: the stock slots of every Highlander weapon in the loadout.
function loader.load(placed)
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
  for _, slot in ipairs(placed) do
    if MODULE[slot] then
      need(MODULE[slot])
    end
  end
  for _, m in ipairs(ORDER) do
    if want[m] then
      require(m)
    end
  end
end

-- A weapon component's install: the modules for the whole loadout once,
-- then this weapon's claim of its slot.
function loader.install(ctx)
  local placed = {}
  for id, w in pairs(ctx.weapons) do
    if id:sub(1, 3) == "hl." then
      placed[#placed + 1] = w.stock_slot
    end
  end
  -- pairs() order differs between machines; the set it builds does not.
  table.sort(placed)
  loader.load(placed)
  if not shared.claim(ctx.stock_slot) then
    error(ctx.id .. ": Highlander has no weapon on " .. ctx.stock_slot)
  end
end

return loader
