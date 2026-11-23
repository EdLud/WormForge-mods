-- Electromagnet: a placed magnet that pulls or pushes mines and missiles for four turns.

local magnet = require("lib/magnet")
local weapon = {}

weapon.requires = { "lib/magnet" }

-- What its field drags can't push it by running into it: stock mines and
-- missiles, the animals among them. Worms, blasts, guns, the Prod and the
-- Fire Punch push it as usual.
local PUSHED_BY = { mines = 0, missiles = 0 }

weapon.record = {
  handling = {
    remember_selection = true,
    ends_turn = true,
  },
}

function weapon.definition()
  local shared = require("lib/shared")
  local fires = shared.fires
  return require("lib/weapon").merge(weapon.record, {
    wep = "weps/baseball_bat.wep",
        panel_icon = "sprites/electromagnet/ico_magnet.png",
    panel_icons = { "sprites/electromagnet/ico_magnet_blue.png" },
        worm_sprites = {
          wdynlnk = "sprites/electromagnet/wmag2lnk.png",
          wdynlnku = "sprites/electromagnet/wmag2lnku.png",
          wdynlnkd = "sprites/electromagnet/wmag2lnkd.png",
        },
    worm_sprites_toggle = { key = "plus_key", worm_sprites = {
          wdynlnk = "sprites/electromagnet/wmaglnk.png",
          wdynlnku = "sprites/electromagnet/wmaglnku.png",
          wdynlnkd = "sprites/electromagnet/wmaglnkd.png",
        } },
    sprites = {
          "sprites/electromagnet/magnet.png", "sprites/electromagnet/magnet2.png",
          "sprites/electromagnet/magnet_damaged.png", "sprites/electromagnet/magnet2_damaged.png",
          "sprites/electromagnet/ring_in.png", "sprites/electromagnet/ring_out.png",
          "sprites/electromagnet/magnetsparks.png",
        },
    params = { gpu_prefix = "sprites/electromagnet/" },
    on_fire = function(fire) fires.electromagnet(fire) end,
  })
end

function weapon.setup()
  local function sq(v) return v * v end

  local shared = require("lib/shared")
  local TURNS, HEALTH, LOW_HEALTH = 4, 80, 30
  local BOOM = { id = 100, damage = 50, below = false } -- ExplosionBlast, ExplosionDamage
  local RADIUS = 8 -- conservative planter clearance around the art
  local PLANTER_GRACE = 13 -- 250 ms rounded up at 50 simulation frames/s
  local SINK = (1 / 2) -- in the water it sinks half a pixel a frame
  local SUNK = 200 -- and is gone this far below the surface
  local BODY = "sprites/electromagnet/"
  local FIELD = { range = 170, strength = 14000, max_force = 12, attract_softening = 10, repel_softening = 5 }

  magnet.toggle_with("px.electromagnet")

  local function sprite(m)
    local name = m.pol < 0 and "magnet" or "magnet2"
    if m.health <= LOW_HEALTH then name = name .. "_damaged" end
    return BODY .. name .. ".png"
  end

  local function clear_spawn(a)
    if a:fits(a.x, a.y) then return end
    for d = 1, 24 do
      for _, v in ipairs({ {0, 1}, {-1, 1}, {1, 1}, {-1, 0}, {1, 0}, {-1, -1}, {1, -1}, {0, -1} }) do
        local x, y = a.x + v[1] * d, a.y + v[2] * d
        if a:fits(x, y) then a:warp { x = x, y = y }; return end
      end
    end
  end

  local function overlaps_planter(x, y, worm)
    return x + RADIUS >= worm.x - 10 and x - RADIUS <= worm.x + 10
      and y + RADIUS >= worm.y - 20 and y - RADIUS <= worm.y + 6
  end

  local function planter_grace(m, a, previous_x, previous_y)
    if not m.planter then return end
    local planter
    for _, worm in ipairs(wa.worms.all()) do
      if worm.id == m.planter_id and worm.hp > 0 then planter = worm; break end
    end
    if not planter or (m.age >= PLANTER_GRACE
      and not overlaps_planter(previous_x, previous_y, planter)
      and not overlaps_planter(m.x, m.y, planter)) then
      a:collision_ignore(m.planter, false)
      m.planter, m.planter_id = nil, nil
    end
  end

  local RELEASE_AFTER = 300
  local function frame(m, a)
    m.age = m.age + 1
    local previous_x, previous_y = m.x, m.y
    if not m.sinking then m.x, m.y, m.vx, m.vy = a.x, a.y, a.vx, a.vy end
    if m.y >= wa.world.water() then
      magnet.discharge(m)
      if not m.sinking then m.sinking = true; a.hits = {} end
      m.vx, m.vy, m.y = 0, 0, m.y + SINK
      a:warp { x = m.x, y = m.y, vx = 0, vy = 0 }
      if m.y >= wa.world.water() + SUNK then
        magnet.remove(m)
        a:remove()
        return
      end
    end
    if m.health <= 0 then
      magnet.trigger_mines(m)
      magnet.remove(m)
      a.y = m.y - 20
      a:explode(BOOM)
      a:remove()
      return
    end
    planter_grace(m, a, previous_x, previous_y)
    if m.turns > 0 then
      m.field.native = not (m.ended_at and m.age - m.ended_at >= RELEASE_AFTER)
      magnet.trigger_mines(m)
      m.spark = (m.spark + 0.02) % 1.4
    end
    local speed = math.sqrt(sq(m.vx) + sq(m.vy))
    m.angle = m.angle + (m.vx < 0 and -1 or 1) * math.min(0.5, 0.04 * speed)
    local s = sprite(m)
    if s ~= m.sprite then a:look(s); m.sprite = s end
    a:gfx({ angle = math.deg(m.angle + math.pi) % 360, depth = wa.depth.OBJECTS })
  end

  shared.fires.electromagnet = function(fire)
    local worm = fire.worm
    local pol = (fire.polarity == 1 or fire.polarity == -1) and fire.polarity or magnet.polarity(worm)
    local m = { pol = pol, turns = TURNS, health = HEALTH,
      x = fire.x or worm.x, y = fire.y or worm.y,
      vx = worm.vx + (worm.facing < 0 and -1 or 1) * 0.3,
      vy = worm.vy - 0.15 }
    local a = wa.actors.spawn({
      sprite = BODY .. (pol < 0 and "magnet.png" or "magnet2.png"),
      x = m.x, y = m.y, vx = m.vx, vy = m.vy, owner = worm,
      body = { physics = "mine", pushed_by = PUSHED_BY }, on = {
        frame = function(actor) frame(m, actor) end,
        hit = function(actor, event) magnet.hit(m, actor, event) end,
      },
    })
    m.a, m.team = a, worm.team
    if a:collision_ignore(worm, true) then m.planter, m.planter_id = worm, worm.id end
    clear_spawn(a)
    m.x, m.y = a.x, a.y
    magnet.add(m, FIELD)
    m.sprite = sprite(m)
  end

  local icon_shown = true
  local function show_mode_icon(worm)
    if not (icon_shown and wa.weapons.panel_icon and shared.owns("px.electromagnet")) then return end
    local attract = worm and magnet.polarity(worm) < 0
    local ok, err = pcall(wa.weapons.panel_icon, "px.electromagnet", attract and 0 or 1)
    if not ok then
      icon_shown = false
      wa.log("electromagnet: mode icon: " .. tostring(err))
    end
  end

  if wa.on.hud then
    wa.on.hud(function()
      local worm = shared.current_worm()
      show_mode_icon(worm)
    end)
  end
  require("lib/weapon_hint").register("px.electromagnet", function(worm)
    return magnet.polarity(worm) < 0 and "Electromagnet: ATTRACT\n+ to repel"
      or "Electromagnet: REPEL\n+ to attract"
  end)
end

return weapon
