-- Random Race: each round of turns races with one set of movement weapons, chosen at random.

local own_time = require("wf-lib/own_time")
local shared = require("lib/shared")

local race = {}

local ART = "sprites/random_race/"
-- What each race puts in the inventory; parkour and anti_fall switch those on at turn start.
-- `equip` (else the first weapon) replaces a weapon the race took away.
local RACES = {
  { name = "parkour", weapons = { "px.parkour", "px.jump", "stock.low_gravity", "px.anti_fall_damage" },
    banner = ART .. "park_race.png", parkour = true, anti_fall = true, equip = "px.jump" },
  { name = "portal", weapons = { "px.portal_gun", "px.anti_fall_damage" }, banner = ART .. "port_race.png",
    anti_fall = true },
  { name = "wings", weapons = { "px.wings" }, banner = ART .. "wing_race.png" },
  { name = "helicopter", weapons = { "px.helicopter" }, banner = ART .. "heli_race.png" },
  { name = "rope", weapons = { "stock.ninja_rope", "stock.parachute" }, banner = ART .. "rope_race.png" },
}
local AIR_STEP, AIR_LIMIT = 0.1, 3 -- pixels/frame
local AIR_STATES = { jumping = true, falling = true, tumbling = true, hit = true, blasted = true, drilling = true }
local BANNER_W, BANNER_H = 400, 200
local GROW, HOLD, FADE = 25, 190, 20 -- frames

function race.install(ctx)
  local draw, managed, seen = {}, {}, {}
  for _, r in ipairs(RACES) do
    local placed = true
    for _, id in ipairs(r.weapons) do placed = placed and ctx.weapons[id] ~= nil end
    if placed then
      draw[#draw + 1] = r
      for _, id in ipairs(r.weapons) do
        if not seen[id] then managed[#managed + 1], seen[id] = id, true end
      end
    end
  end
  if #draw == 0 then
    wa.log("Random Race: no race has all its weapons on the panel; off")
    return
  end
  local banners = {}
  for _, r in ipairs(draw) do banners[#banners + 1] = r.banner end
  wa.assets.load({ sprites = banners, gpu_prefix = ART })

  local placing = wa.world.placing or function() return false end
  local current, lead, shown_at = nil, nil, nil
  local pending, begun, active = nil, false, {}

  local function choose()
    current = draw[wa.random(1, #draw)]
    local give = {}
    for _, id in ipairs(current.weapons) do give[id] = true end
    local groups = {}
    for _, w in ipairs(wa.worms.all()) do
      if not groups[w.ammo_group] then
        groups[w.ammo_group] = true
        for _, id in ipairs(managed) do w:ammo(id, { set = give[id] and -1 or 0 }) end
      end
    end
    shown_at = wa.world.frame()
    wa.log("Random Race: " .. current.name .. " race")
  end

  local function team_alive(team)
    for _, w in ipairs(wa.worms.all()) do
      if w.team == team and w.hp > 0 then return true end
    end
    return false
  end

  -- The turn's first frame after placement: a new race whenever the leading team's turn comes round.
  local function begin(worm)
    if not begun then
      begun = true
      if not lead or not team_alive(lead) then lead = worm.team end
      if worm.team == lead then choose() end
    end
    -- WA hands the worm its team's last weapon, which would still fire if
    -- this race took it away.
    local held = worm.weapon
    if held and seen[held] and worm:ammo(held) == 0 then worm:equip(current.equip or current.weapons[1]) end
    if current.parkour or current.anti_fall then active[worm.id] = true end
    if current.parkour then
      if shared.parkour_on then shared.parkour_on(worm) end
      if shared.swim_suit_on then shared.swim_suit_on(worm) end
    end
    if current.anti_fall and shared.anti_fall_damage_on then shared.anti_fall_damage_on(worm) end
  end

  wa.on.turn_start(function(ev)
    if ev.worm then pending = ev.worm.id end
  end)

  wa.on.turn_end(function()
    pending, begun, active = nil, false, {}
  end)

  local function steer(worm)
    if not AIR_STATES[worm.state] then return end
    local k = worm.keys
    for _ = 1, own_time.frames(worm) do
      if k.up and worm.vy >= -AIR_LIMIT then worm.vy = worm.vy - AIR_STEP end
      if k.down and worm.vy <= AIR_LIMIT then worm.vy = worm.vy + AIR_STEP end
      if k.left and worm.vx >= -AIR_LIMIT then worm.vx = worm.vx - AIR_STEP end
      if k.right and worm.vx <= AIR_LIMIT then worm.vx = worm.vx + AIR_STEP end
    end
  end

  wa.on.worm_message(function(worm)
    if not worm.turn then return end
    if pending == worm.id and not placing() then
      pending = nil
      begin(worm)
    end
    if active[worm.id] and current.parkour and worm.hp > 0 then steer(worm) end
  end, { msgs = { wa.msg.FRAME_FINISH } })

  wa.on.hud(function()
    if not shown_at then return end
    local age = wa.world.frame() - shown_at
    if age < 0 or age >= HOLD + FADE then return end
    local alpha = age < GROW and (age + 1) / GROW or age < HOLD and 1 or 1 - (age - HOLD) / FADE
    local w, h = wa.hud.size()
    wa.hud.sprite({
      sprite = current.banner, x = (w - BANNER_W) // 2, y = h // 4 - BANNER_H // 2,
      color = math.floor(alpha * 255) * 0x1000000 + 0xFFFFFF,
    })
  end)
end

return race
