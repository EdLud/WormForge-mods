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

-- Weapon -> the module with its own code. A weapon missing here is its
-- claim alone (a PX record, or PX's changes to WA's own).
local MODULE = {
  ["px.super_drill"] = "weapons/super_drill",
  ["px.fire_jump"] = "weapons/fire_jump",
  ["px.sniper_rifle"] = "weapons/sniper_rifle",
  ["px.double_bazooka"] = "weapons/double_bazooka",
  ["px.chilli_bomb"] = "weapons/chilli_bomb",
  ["px.nuke_rocket"] = "weapons/nuke_rocket",
  ["px.helicopter"] = "weapons/helicopter",
  ["px.hot_air_balloon"] = "weapons/hot_air_balloon",
  ["px.hang_glider"] = "weapons/hang_glider",
  ["px.swim_suit"] = "weapons/swim_suit",
  ["px.gravity_control"] = "weapons/wind_gravity",
  ["px.wind_changer"] = "weapons/wind_gravity",
  ["px.jump"] = "weapons/jump",
  ["px.laser_gun"] = "weapons/laser_gun",
  ["px.super_tele"] = "weapons/super_tele",
  ["px.electric_grenade"] = "weapons/electrical",
  ["px.lightning_strike"] = "weapons/electrical",
  ["px.javelin"] = "weapons/javelin",
  ["px.ice_arrow"] = "weapons/ice_arrow",
  ["px.valyrian_fire"] = "weapons/valyrian_fire",
  ["px.reinforcement"] = "weapons/reinforcement",
  ["px.bowling_ball_strike"] = "weapons/bowling_ball",
  ["px.ferret"] = "weapons/ferret",
  ["px.electromagnet"] = "weapons/electromagnet",
  ["px.crate_strike"] = "weapons/crate_strike",
  ["px.sentry_gun"] = "weapons/sentry_gun",
  ["px.sentry_laser"] = "weapons/sentry_laser",
  ["px.kamikaze_rocket"] = "weapons/kamikaze_rocket",
  ["px.weapon_crate"] = "weapons/weapon_crate",
  ["px.portal_gun"] = "weapons/portal_gun",
}

-- Module -> modules whose helpers it reads as it loads. Their hooks act only
-- on what their own weapon made, or on Highlander's own weapons (by id, and
-- shared.owns).
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
local loaded, placed_ids = false, nil

-- Which weapons this match places, by id, sorted: the modules to load. The
-- scheme installs first and calls this too.
function loader.place(ctx)
  if placed_ids then
    return placed_ids
  end
  local ids = {}
  for id in pairs(ctx.weapons) do
    ids[#ids + 1] = id
  end
  -- pairs() order differs between machines; the set it builds does not.
  table.sort(ids)
  placed_ids = ids
  return ids
end

-- The modules every placed weapon needs, once, in rules.lua's order.
function loader.load(ids)
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
  for _, id in ipairs(ids) do
    if MODULE[id] then
      need(MODULE[id])
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
  local options
  if ctx.id == "px.helicopter" then
    options = { fuel = ctx.option("fuel") }
    shared.helicopter_fuel = options.fuel
  elseif ctx.id == "px.sentry_gun" then
    shared.sentry_gun.health = ctx.option("health")
  elseif ctx.id == "px.sentry_laser" then
    shared.sentry_laser.health = ctx.option("health")
  end
  if not shared.claim(ctx.id, options) then
    error(ctx.id .. ": not a Highlander weapon")
  end
end

return loader
