-- Team17 3.3's own scripts (scheme_team17): crates and 30 HP for a kill, a
-- health crate every few minutes, one F4 and one F7 weapon a turn. A tray at
-- the top of the screen shows F4, F7 and the Super Tele, greyed once used up
-- for the turn.

local crate_spot = require("lib/crate_spot")
local rules_window = require("lib/rules_window")

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
local SET_NAMES = { "F4", "F7" }

local RULES = {
  { "Team17 3.3", color = "purple" },
  { "Only the Super Tele ends the turn. Mines have random fuses.", color = "cyan" },
  { "One F4 and one F7 weapon a turn, with much less power.", color = "green" },
  { "A kill drops a weapon and a utility crate and gives 30 HP.", color = "yellow" },
  { "Have lots of fun!", color = "purple" },
}

function team17.install(ctx)
  local placed = ctx.weapons
  rules_window.install(RULES)
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
  local current = nil
  wa.on.death(function(ev)
    local killer, victim = current, ev.victim
    if killer and killer.id ~= victim.id and killer.hp > 0 and killer.team ~= victim.team then
      killer:heal(KILL_HP)
      utility_crate()
      weapon_crate()
    end
  end)

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

  -- The tray, per team: the Super Tele's cell (greyed by the engine while
  -- its delay runs, a lock included) and a text cell for each set, greyed
  -- while none of its weapons can be used. Oldest at the right, so they
  -- read F4, F7, Super Tele.
  local tray = wa.hud and wa.hud.tray
  local cells = {} -- team -> { set n -> { entry, greyed } }
  local function usable(worm, set)
    for _, id in ipairs(set) do
      if placed[id] and worm:delay(id) == 0 and worm:ammo(id) ~= 0 then return true end
    end
    return false
  end
  local function show(worm)
    if not tray then return end
    if placed[SUPER_TELE] and worm:ammo(SUPER_TELE) ~= 0 then
      tray.add{ weapon = SUPER_TELE, team = worm.team }
    end
    local team = cells[worm.team] or {}
    cells[worm.team] = team
    for n = #SETS, 1, -1 do
      team[n] = team[n] or { entry = tray.add{ text = SET_NAMES[n], team = worm.team }, greyed = false }
    end
  end
  local function grey(worm)
    for n, c in ipairs(cells[worm.team] or {}) do
      local greyed = not usable(worm, SETS[n])
      if greyed ~= c.greyed then
        c.entry:set{ greyed = greyed }
        c.greyed = greyed
      end
    end
  end

  wa.on.turn_start(function(ev)
    turn_on = true
    if ev.worm then
      current = ev.worm
      show(ev.worm)
      grey(ev.worm)
    end
    for _, c in ipairs(wa.crates.all()) do c.camera = false end
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
    if turn_on then
      health_timer()
      if current then grey(current) end
    end
  end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.WEAPON_RELEASED } })
end

return team17
