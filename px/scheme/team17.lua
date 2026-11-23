-- Team17 3.3's own scripts (scheme_team17): crates and 30 HP for a kill, a
-- health crate every few minutes, one F4 and one F7 weapon a turn.

local crate_spot = require("lib/crate_spot")

local team17 = {}

-- extra_crates.txt's lists, by the weapons' ids; a weapon not on the panel
-- gives what PX gives for a name it can't find.
local UTILITIES = {
  "px.crate_grabber", "px.wind_changer", "px.health_zone", "stock.ninja_rope", "px.magnetic_missile",
  "px.sentry_gun", "px.sentry_laser", "stock.select_worm", "stock.low_gravity", "px.double_jump",
  "stock.damage_x2", "stock.crate_spy", "stock.double_turn_time", "stock.crate_shower",
}
local UTILITY_FALLBACK = "stock.low_gravity"
local NORMAL = {
  "px.double_bazooka", "px.mine_launcher", "px.bible_launcher", "px.gravler", "px.frag_grenade",
  "px.big_cluster_bomb", "px.chilli_bomb", "px.poison_grenade", "px.real_shotgun", "px.hotchkiss",
  "px.laser_gun", "px.shadow_bolt", "px.bomb_omb", "px.thrown_dynamite", "px.mole_herd_launcher",
  "px.bowling_ball", "px.underwater_bomb", "px.bulldozer", "px.tazer",
}
local SUPER = {
  "px.burning_sheep_launcher", "px.golden_grenade", "px.multi_bolt", "px.thrown_ming_vase",
  "px.normal_barrel", "stock.holy_grenade", "px.hellish_hand_grenade", "px.super_gravedigger",
  "px.submarine_attack", "px.valyrian_fire", "px.super_remote_roller", "px.buffalo_of_lies",
}
local AMOUNT = { ["px.underwater_bomb"] = 3 }
local NORMAL_IN_TEN = 6 -- of ten weapon crates, from NORMAL; the rest from SUPER
local KILL_HP = 30
local HEALTH, HEALTH_BASE, HEALTH_SPREAD, RETRY = 75, 18000, 7200, 60 -- HP, frames
local MAX_CRATES = 4 -- a health crate only while at most this many are out

-- weapon_manager.txt: firing one of a set locks the set and the Super Tele
-- for the rest of the turn.
local SETS = {
  { "stock.fire_punch", "stock.dragon_ball", "stock.prod" },
  { "stock.blow_torch", "stock.pneumatic_drill", "stock.girder" },
}
local SUPER_TELE = "px.super_tele"

local RULES = {
  { "Team17 3.3", color = "purple" },
  { "Only the Super Tele ends the turn. Mines have random fuses.", color = "cyan" },
  { "One F4 and one F7 weapon a turn, with much less power.", color = "green" },
  { "A kill drops a weapon and a utility crate and gives 30 HP.", color = "yellow" },
  { "Have lots of fun!", color = "purple" },
}
local RULES_FRAMES = 500

function team17.install(ctx)
  local placed = ctx.weapons
  local turn_on = false

  local function spawn(kind, contents, amount)
    local x, y = crate_spot.find()
    if not x then return nil end
    local ok, crate = pcall(wa.crates.spawn, {
      x = x, y = y, kind = kind, contents = contents, amount = contents and (amount or 1) or nil,
      health = kind == "health" and HEALTH or nil,
    })
    if not ok then
      wa.log("Team17: no " .. kind .. " crate: " .. tostring(crate))
      return nil
    end
    if crate and turn_on then crate.camera = false end
    return crate
  end

  local function utility_crate()
    local id = UTILITIES[wa.random(1, #UTILITIES)]
    if not placed[id] then id = placed[UTILITY_FALLBACK] and UTILITY_FALLBACK or nil end
    spawn("utility", id)
  end

  local function weapon_crate()
    local list = wa.random(0, 9) < NORMAL_IN_TEN and NORMAL or SUPER
    local id = list[wa.random(1, #list)]
    if placed[id] then spawn("weapon", id, AMOUNT[id]) else spawn("weapon") end
  end

  -- crates_per_kill.txt: the worm whose turn began last, alive and of
  -- another team, is rewarded for each worm whose health reaches 0.
  local current, counted = nil, {}
  local function check_kills()
    for _, w in ipairs(wa.worms.all()) do
      if w.hp <= 0 and not counted[w.id] then
        counted[w.id] = true
        local killer = current
        if killer and killer.id ~= w.id and killer.hp > 0 and killer.team ~= w.team then
          killer:heal(KILL_HP)
          utility_crate()
          weapon_crate()
        end
      elseif w.hp > 0 then
        counted[w.id] = nil
      end
    end
  end

  -- extra_crates.txt: counted in the frames of the turns.
  local health_at, health_count = 0, 0
  local function health_timer()
    if health_at == 0 then health_at = HEALTH_BASE + wa.random(0, HEALTH_SPREAD - 1) end
    if health_count >= health_at then
      health_at, health_count = 0, 0
      if #wa.crates.all() <= MAX_CRATES and spawn("health") then
        wa.hud.message_top("Health crate spawned.")
      else
        health_at = RETRY
      end
    end
    health_count = health_count + 1
  end

  -- Locks, per ammo group, to lift when the turn ends.
  local locks = {}
  local function lock(worm, set)
    local held = locks[worm.ammo_group] or {}
    for _, id in ipairs(set) do
      if placed[id] and worm:delay(id) == 0 then
        worm:delay(id, -1)
        held[#held + 1] = id
      end
    end
    locks[worm.ammo_group] = held
  end
  local function unlock()
    local by_group = {}
    for _, w in ipairs(wa.worms.all()) do by_group[w.ammo_group] = by_group[w.ammo_group] or w end
    for group, held in pairs(locks) do
      local w = by_group[group]
      for _, id in ipairs(w and held or {}) do
        if w:delay(id) == -1 then w:delay(id, 0) end
      end
    end
    locks = {}
  end

  local in_set = {}
  for n, set in ipairs(SETS) do
    for _, id in ipairs(set) do in_set[id] = n end
  end

  local rules_window, rules_at = nil, nil
  wa.on.turn_start(function(ev)
    turn_on = true
    if ev.worm then current = ev.worm end
    for _, c in ipairs(wa.crates.all()) do c.camera = false end
    if not rules_window then
      rules_window = wa.hud.window({ lines = RULES, align = "top", y = 60, over_panel = false })
      rules_at = wa.world.frame()
    end
  end)
  wa.on.turn_end(function()
    turn_on = false
    for _, c in ipairs(wa.crates.all()) do c.camera = nil end
    unlock()
  end)

  local last_frame = nil
  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.WEAPON_RELEASED then
      local n = worm.turn and in_set[worm.weapon]
      if n then
        local set = { SUPER_TELE }
        for _, id in ipairs(SETS[n]) do set[#set + 1] = id end
        lock(worm, set)
      end
      return
    end
    local frame = wa.world.frame()
    if frame == last_frame then return end
    last_frame = frame
    check_kills()
    if turn_on then health_timer() end
    if rules_at and frame - rules_at >= RULES_FRAMES then
      rules_window:close()
      rules_at = nil
    end
  end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.WEAPON_RELEASED } })
end

return team17
