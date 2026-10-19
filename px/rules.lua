-- Highlander as the test suites run it: the Highlander profile's match. As
-- in a match, WA's own weapons the profile deals sit on their own slots and
-- every Highlander weapon on one past WA's 70, in id order; the hl.rules
-- add-on deals from the pools the weapons suggest (mod.toml) and the profile
-- sets (profiles/Highlander.toml). They install as the engine installs a
-- profile's components: hl.rules first (before_weapons), then each weapon, in
-- slot order. A real match runs the components the player's profile selects;
-- the engine never runs this file.
--
-- A port of Project X's `scheme_hl_0rang3` (Highlander 0rang3 1.1): every
-- worm is dealt one weapon from each of three pools at the start of the
-- match, may use each once a turn, and takes everything a worm it kills
-- carried (scheme/rules.lua).
local root = HIGHLANDER_ROOT or "mods/px/"

-- WA's 71 slots in order: where each weapon sits decides the deal's order.
local STOCK = {
  "bazooka", "homing_missile", "mortar", "homing_pigeon", "sheep_launcher",
  "grenade", "cluster_bomb", "banana_bomb", "battle_axe", "earthquake", "shotgun",
  "handgun", "uzi", "minigun", "longbow", "fire_punch", "dragon_ball", "kamikaze",
  "suicide_bomber", "prod", "dynamite", "mine", "sheep", "super_sheep",
  "aqua_sheep", "mole_bomb", "air_strike", "napalm_strike", "mail_strike",
  "mine_strike", "mole_squadron", "blow_torch", "pneumatic_drill", "girder",
  "baseball_bat", "girder_pack", "ninja_rope", "bungee", "parachute", "teleport",
  "scales_of_justice", "super_banana", "holy_grenade", "flame_thrower",
  "salvation_army", "mb_bomb", "petrol_bomb", "skunk", "ming_vase",
  "sheep_strike", "carpet_bomb", "mad_cow", "old_woman", "donkey",
  "nuclear_test", "armageddon", "skip_go", "surrender", "select_worm", "freeze",
  "magic_bullet", "jet_pack", "low_gravity", "fast_walk", "laser_sight",
  "invisibility", "damage_x2", "crate_spy", "double_turn_time", "crate_shower",
}
local INDEX = {}
for i, name in ipairs(STOCK) do INDEX[name] = i end

-- Each weapon's hl.rules settings: pool and cavern, as mod.toml suggests
-- them for PX's weapons and the profile sets them for WA's own.
local settings = {}
-- `header`: a table header naming the weapon (the profile's); else the
-- weapon is the last `id =` seen (mod.toml's components).
-- Highlander's weapons: mod.toml's components that enter through
-- components/weapon.lua (the others, reddaz's, have their own files).
local highlander, own_options = {}, {}
local function read(path, header)
  local f = assert(io.open(root .. path, "r"))
  local id, option_key, in_options
  for line in f:lines() do
    if line:match("^%[") then
      in_options = line == "[[components.options]]"
      option_key = nil
    end
    id = line:match('^id = "([%w_%.]+)"') or (header and line:match(header)) or id
    if id and line == 'entry = "components/weapon.lua"' then highlander[id] = true end
    if in_options then
      option_key = line:match('^key = "([%w_]+)"') or option_key
      local default = line:match("^default = (%d+)$")
      if id and option_key and default then
        own_options[id] = own_options[id] or {}
        own_options[id][option_key] = tonumber(default)
      end
    end
    local pool = line:match('^pool = "([%w ]+)"')
    local cavern = line:match("^cavern = (%a+)")
    if id and (pool or cavern) then
      settings[id] = settings[id] or {}
      if pool then settings[id].pool = pool end
      if cavern then settings[id].cavern = cavern == "true" end
    end
  end
  f:close()
end
read("mod.toml")
read("profiles/Highlander.toml", '^%[weapon_options%."hl%.rules"%."([%w_%.]+)"%]')

-- The match's weapons in slot order: WA's own with a pool on their own
-- slots, then Highlander's past WA's 70, in id order.
local placed, ids = {}, {}
for id in pairs(settings) do
  local stock = id:match("^stock%.(.+)$")
  if stock then
    placed[#placed + 1] = { id = id, slot = stock }
  end
end
table.sort(placed, function(a, b) return INDEX[a.slot] < INDEX[b.slot] end)
for id in pairs(highlander) do ids[#ids + 1] = id end
table.sort(ids)
for _, id in ipairs(ids) do placed[#placed + 1] = { id = id } end
local weapons = {}
for _, w in ipairs(placed) do
  local s = settings[w.id] or {}
  w.options = { pool = s.pool or "not dealt", cavern = s.cavern ~= false }
  weapons[w.id] = w
end

-- hl.rules first, then each weapon claiming its slot.
local loader = require("components/loader")
require("components/highlander").install({ id = "hl.rules", weapons = weapons, placed = placed })
for _, w in ipairs(placed) do
  if highlander[w.id] then
    HIGHLANDER_CLAIMING = w.id
    local options = own_options[w.id] or {}
    loader.install({ id = w.id, weapons = weapons, placed = placed,
      options = options, option = function(key)
        assert(options[key] ~= nil, w.id .. " has no option " .. key)
        return options[key]
      end })
  end
end
HIGHLANDER_CLAIMING = nil
