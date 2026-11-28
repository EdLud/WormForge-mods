-- Fan: a placed fan that blows for a few turns. On its side it adds to the
-- wind; upright it lifts Hang-Gliders, Hot Air Balloons and flames. Knock its
-- grate off and its blades hit whatever stands in front of them.

local weapon = {}
local ID = "px.fan"
local ART = "sprites/fan/"
local SND = "sounds/fan/"

weapon.requires = { "lib/turn_controls" }

weapon.definition = {
  copy_from = "stock.mine",
  name = "Fan",
  panel_icon = ART .. "ico_fan.png",
  handling = {
    ends_turn = false,
  },
  -- The take-out, and the same frames reversed as it leaves the worm's hands.
  worm_sprites = {
    weaponlnk = ART .. "wfanlnk.png", weaponlnku = ART .. "wfanlnku.png", weaponlnkd = ART .. "wfanlnkd.png",
    wthrow = ART .. "wfanbak.png", wthrowu = ART .. "wfanbaku.png", wthrowd = ART .. "wfanbakd.png",
  },
  sprites = {
    ART .. "body.png", ART .. "body_vertical.png", ART .. "blade.png", ART .. "blade_idle.png",
    ART .. "grate.png", ART .. "arrow.png",
  },
  sounds = { SND .. "fan_start.wav", SND .. "fan_break.wav" },
  params = { worm_sprites_animate = true, gpu_prefix = ART },
  on_fire = function(fire) require("lib/shared").fires.fan(fire) end,
}

function weapon.setup()
  local shared = require("lib/shared")
  local airflow = require("lib/airflow")
  local health_label = require("lib/sentry_health")

  local HEALTH = 55
  local MAX_FORCE = 5
  local SCALE = 0.6 -- the placed fan's art is drawn at 0.6
  local BASE = 12 -- pixels from the art's anchor down to the bottom of its stand
  -- The body's outline for each way it stands, and how far right of the
  -- outline's feet the art is drawn (the feet are the middle of its bottom row).
  local MASK = { right = ART .. "mask_right.png", left = ART .. "mask_left.png", upright = ART .. "mask_vertical.png" }
  local ART_DX = { right = 1, left = 0, upright = 2 }
  local SLIDE_FRICTION = 0.20 -- pixels/frame lost on the ground, as a sentry's
  local CONTACT_WORM, CONTACT_PROJECTILE = 0.5, 0.25 -- the share of a touch's speed it takes
  local WIND_PER_FORCE, MAX_WIND = 0.07, 0.34
  local WIND_EPS = 1 / 4096
  local COLUMN_HALF_WIDTH, COLUMN_PER_FORCE = 15, 64
  local BLADE_DAMAGE, BLADE_DAMAGE_STEP, BLADE_SELF_DAMAGE = 14, 4, 3
  local BLADE_PUSH, BLADE_COOLDOWN, BLADE_FIRST = 5, 5, 30
  local BLADE_HIT_SOUND = 85
  local OBJECT_DAMAGE = { oil = 100, crate = 100, mine = BLADE_DAMAGE }
  local BOOM = { damage = 25, id = 100, below = false }
  local SINK = 0.5 -- in the water it sinks half a pixel a frame
  local SUNK = 200 -- and is gone this far below the surface
  local PLANTER_GRACE = 13 -- 250 ms rounded up at 50 simulation frames/s
  local GRATE_LIFE, GRATE_SPIN = 100, 0.6
  local FLAME_RADIUS = 24
  local TEAM_TINT = { 0xFF6447, 0x4764FF, 0x47FF64, 0xE6E647, 0xE647E6, 0x47E6E6 }
  local NO_TEAM_TINT = 0x9A9A9A
  local SUNK_TINT = { 90 / 255, 90 / 255, 240 / 255 }
  local HALF_PI = math.pi / 2

  local fans = {}
  local grates = {} -- knocked-off grates, falling
  local force, vertical = {}, {} -- worm id -> the force and mode it places with
  local plus_held = {}
  local reducer = {} -- worm id -> blade damage already taken off this turn

  local fan_ids = {} -- actor id -> true, for the fans' bodies
  local function trunc(x) return x >= 0 and math.floor(x) or -math.floor(-x) end

  local function push(f, a, vx, vy)
    if vx == 0 and vy == 0 then return end
    f.vx, f.vy = a.vx + vx, a.vy + vy
    a:warp { x = a.x, y = a.y, vx = f.vx, vy = f.vy }
  end

  local function active(f)
    return f.alive and not f.sinking and f.turns > 0
  end

  -- The art's anchor: the stand's bottom sits on the ground below the body.
  local function anchor_y(f) return f.y - BASE end
  local function art_x(f) return f.x + f.dx end

  local function blade_at(f)
    local y = anchor_y(f) - 1
    if f.vertical then return art_x(f), y - SCALE * 10 end
    return art_x(f) + f.side * SCALE * 10, y - SCALE * 14
  end

  local function remove(f)
    f.alive = false
    fan_ids[f.a.id] = nil
    airflow.remove(f.source)
    for i, other in ipairs(fans) do
      if other == f then table.remove(fans, i); break end
    end
  end

  local function knock_grate(f, a)
    f.grate = false
    local x, y = blade_at(f)
    local eject = wa.random(-40, 40) / 100
    local speed = wa.random(40, 70) / 10
    grates[#grates + 1] = {
      x = x, y = y, vx = speed * wa.math.sin(eject), vy = -speed * wa.math.cos(eject),
      angle = f.vertical and -HALF_PI or 0, flip = (not f.vertical and f.side < 0) and -1 or 1,
      life = GRATE_LIFE,
    }
    wa.sound.play(a, SND .. "fan_break.wav")
  end

  -- A hit on the fan: fire and the Blow Torch only burn it, a blast or the
  -- Prod knocks the grate off past 10 damage, anything else at once.
  local function hurt(f, a, ev)
    if not f.alive then return end
    local kind = ev.kind
    local damage = math.max(0, ev.damage or 0)
    if kind == "percent" then damage = trunc(f.health * damage / 100) end
    if f.grate and kind ~= "fire" and kind ~= "blow_torch"
        and ((kind ~= "prod" and kind ~= "blast") or damage > 10) then
      knock_grate(f, a)
    end
    f.health = f.health - damage
    push(f, a, ev.vx or 0, ev.vy or 0)
  end

  -- What runs into it pushes it, as a sentry: a worm with half its speed, a
  -- projectile with a quarter. A Javelin that hit it already pushed it.
  local function touched(f, a, ev)
    local other = ev.other
    if not (f.alive and other) then return end
    if other.id and f.script_hits[other.id] then f.script_hits[other.id] = nil; return end
    if other.kind == "actor" and fan_ids[other.id] then return end
    local share = other.kind == "worm" and CONTACT_WORM or CONTACT_PROJECTILE
    push(f, a, (ev.vx or 0) * share, (ev.vy or 0) * share)
  end

  -- The blades, unguarded: a hit every 5 frames on what is in front of them,
  -- thrown away from the fan within 90 degrees of the airflow.
  local function inside(o, cx, cy, hw, hh)
    return math.abs(o.x - cx) <= hw and math.abs(o.y - cy) <= hh
  end

  local function throw(f)
    local angle = math.rad(wa.random(-90, 90))
    if f.vertical then angle = angle + HALF_PI
    elseif f.side < 0 then angle = angle + math.pi end
    return wa.math.cos(angle) * BLADE_PUSH, -wa.math.sin(angle) * BLADE_PUSH
  end

  local function blades(f, a)
    if f.blade_wait > 0 then f.blade_wait = f.blade_wait - 1; return end
    local bx, by = blade_at(f)
    local cx, cy, hw, hh
    if f.vertical then cx, cy, hw, hh = bx, by - 4, 14, 6
    else cx, cy, hw, hh = bx + 5 * f.side, by, 6, 14 end
    local near = { near = { cx, cy, 24 } }
    local hits = 0
    for _, w in ipairs(wa.worms.all(near)) do
      if w.hp > 0 and inside(w, cx, cy, hw + 4, hh + 8) then
        local damage = BLADE_DAMAGE - (reducer[w.id] or 0)
        if damage < 1 then damage = 1
        else reducer[w.id] = (reducer[w.id] or 0) + BLADE_DAMAGE_STEP end
        local vx, vy = throw(f)
        w:hit { amount = damage, vx = vx, vy = vy }
        hits = hits + 1
      end
    end
    for _, m in ipairs(wa.missiles.all(near)) do
      if inside(m, cx, cy, hw + 5, hh + 5) then
        m:impulse(throw(f))
        hits = hits + 1
      end
    end
    for _, list in ipairs({ wa.mines, wa.oil, wa.crates }) do
      for _, o in ipairs(list.all(near)) do
        if inside(o, cx, cy, hw + 5, hh + 5) then
          local vx, vy = throw(f)
          o:hit(OBJECT_DAMAGE[o.kind] or BLADE_DAMAGE, vx, vy)
          hits = hits + 1
        end
      end
    end
    -- Placed objects (magnets, sentries, other fans), not what flies.
    for _, other in ipairs(wa.actors.all(near)) do
      if other.id ~= a.id and other.grab == true and inside(other, cx, cy, hw + 5, hh + 5) then
        local vx, vy = throw(f)
        if other:hit(BLADE_DAMAGE, vx, vy) then hits = hits + 1 end
      end
    end
    for _ = 1, hits do
      wa.sound.play(a, BLADE_HIT_SOUND)
      f.health = f.health - BLADE_SELF_DAMAGE
      f.blade_wait = BLADE_COOLDOWN
    end
  end

  -- Blade spin and the airflow arrows.
  local function animate(f)
    for i = 1, #f.arrows do f.arrows[i] = f.arrows[i] + f.arrow_speed end
    if f.arrows[1] and f.arrows[1] >= f.arrow_distance * 10 then table.remove(f.arrows, 1) end
    local target = 0
    if active(f) then
      target = f.max_speed
      if f.next_arrow <= 0 then
        if #f.arrows < 6 then f.arrows[#f.arrows + 1] = 0 end
        f.next_arrow = f.arrow_period
      else
        f.next_arrow = f.next_arrow - 1
      end
    end
    local step = 0.006
    if f.speed > target + step then f.speed = f.speed - step
    elseif f.speed < target - step then f.speed = f.speed + step
    else f.speed = target end
    f.cycle = (f.cycle + f.speed) % 1
  end

  -- The fan stands up to 30 pixels above its feet at (x, y).
  local function overlaps_planter(x, y, worm)
    return x + 13 >= worm.x - 10 and x - 13 <= worm.x + 10
      and y >= worm.y - 20 and y - 30 <= worm.y + 6
  end

  local function planter_grace(f, a, previous_x, previous_y)
    if not f.planter then return end
    local planter
    for _, worm in ipairs(wa.worms.all()) do
      if worm.id == f.planter_id and worm.hp > 0 then planter = worm; break end
    end
    if not planter or (f.age >= PLANTER_GRACE
      and not overlaps_planter(previous_x, previous_y, planter)
      and not overlaps_planter(f.x, f.y, planter)) then
      a:collision_ignore(f.planter, false)
      f.planter, f.planter_id = nil, nil
    end
  end

  local function frame(f, a)
    if not f.alive then return end
    f.age = f.age + 1
    local now = wa.world.frame()
    for id, at in pairs(f.script_hits) do
      if at < now - 1 then f.script_hits[id] = nil end
    end
    local previous_x, previous_y = f.x, f.y
    if not f.sinking then
      f.x, f.y, f.vx, f.vy = a.x, a.y, a.vx, a.vy
      -- On the ground it slides to a stop.
      if f.vy == 0 and f.vx ~= 0 and a:on_feet() then
        local vx = f.vx
        if math.abs(vx) <= SLIDE_FRICTION then vx = 0
        elseif vx > 0 then vx = vx - SLIDE_FRICTION
        else vx = vx + SLIDE_FRICTION end
        f.vx, a.vx = vx, vx
      end
    end
    if f.y >= wa.world.water() then
      if not f.sinking then f.sinking, f.turns, a.gravity = true, 0, 0 end
      f.y = f.y + SINK
      a:warp { x = f.x, y = f.y, vx = 0, vy = 0 }
      if f.y >= wa.world.water() + SUNK then
        remove(f)
        a:remove()
        return
      end
    end
    if f.health <= 0 then
      remove(f)
      a.y = anchor_y(f) - 20
      a:explode(BOOM)
      a:remove()
      return
    end
    planter_grace(f, a, previous_x, previous_y)
    animate(f)
    if active(f) and not f.grate then blades(f, a) end
    local s = f.source
    if f.vertical then s.x, s.y = art_x(f), anchor_y(f) else s.x, s.y = blade_at(f) end
    s.on = active(f)
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

  shared.fires.fan = function(fire)
    local worm = fire.worm
    local side = worm.facing < 0 and -1 or 1
    local strength = force[worm.id] or MAX_FORCE
    local f = {
      team = worm.team, alliance = worm.alliance or 0, side = side,
      vertical = vertical[worm.id] == true, force = strength,
      health = HEALTH, turns = 7 - strength, grate = true, alive = true, age = 0,
      cycle = 0, speed = 0, max_speed = 0.06 + strength * 0.025,
      arrows = {}, next_arrow = 0,
      arrow_speed = 2 + strength * 3, arrow_period = 40 // strength,
      arrow_distance = 6 + strength * 12, arrow_scale = 1 + strength * 0.1,
      blade_wait = BLADE_FIRST, script_hits = {},
    }
    local shape = f.vertical and "upright" or (side < 0 and "left" or "right")
    f.dx = ART_DX[shape]
    -- The sentries' body: its outline's feet at x, y, falling and sliding.
    local a = wa.actors.spawn({
      sprite = false, x = fire.x or worm.x, y = fire.y or worm.y,
      vx = worm.vx * 0.5 + side * 0.3, vy = worm.vy * 0.5 - 0.15,
      origin = "bottom", owner = worm, persist = true, gravity = 1,
      body = { shape = MASK[shape], hits = { land = true, objects = true } },
      on = {
        frame = function(actor) frame(f, actor) end,
        hit = function(actor, event) hurt(f, actor, event) end,
        touched = function(actor, event) touched(f, actor, event) end,
      },
    })
    f.a = a
    fan_ids[a.id] = true
    if a:collision_ignore(worm, true) then f.planter, f.planter_id = worm, worm.id end
    clear_spawn(a)
    f.x, f.y = a.x, a.y
    f.source = airflow.add({ x = art_x(f), y = anchor_y(f), dx = f.vertical and 0 or side, dy = f.vertical and -1 or 0,
      on = false, half_width = COLUMN_HALF_WIDTH, reach = strength * COLUMN_PER_FORCE, power = 0.5 + 0.1 * strength })
    fans[#fans + 1] = f
    wa.sound.play(worm, SND .. "fan_start.wav")
  end

  -- The wind: the turn's own, plus every active fan on its side, within
  -- +-0.34. The base is whatever wind the fans didn't make: WA rolls the
  -- turn's after the turn has started, and the Wind Changer sets its own.
  local base, written, contributed
  local function update_wind()
    local sum = 0
    for _, f in ipairs(fans) do
      if not f.vertical and active(f) then sum = sum + WIND_PER_FORCE * f.force * f.side end
    end
    if sum == 0 and not contributed then written = nil; return end
    local now = wa.world.wind()
    if not written or math.abs(now - written) > WIND_EPS then
      base = now
      if sum ~= 0 then wa.log(string.format("Fan: wind %.4f, fans add %.4f", base, sum)) end
    end
    local total = base + sum
    if sum ~= 0 then total = math.max(-MAX_WIND, math.min(MAX_WIND, total)) end
    if math.abs(total - now) > WIND_EPS then wa.world.set_wind(total) end
    written, contributed = total, sum ~= 0
  end

  wa.on.frame(function()
    update_wind()
    -- Upright fans throw flames upward: the stock flame push spreads them
    -- out from the blades, standing in for a column of rising air.
    for _, f in ipairs(fans) do
      if f.vertical and active(f) then
        local x, y = blade_at(f)
        wa.fire.repel { x = x, y = y, radius = FLAME_RADIUS, power = 4 + 2 * f.force }
      end
    end
    local g = wa.world.gravity()
    for i = #grates, 1, -1 do
      local p = grates[i]
      p.life = p.life - 1
      if p.life <= 0 then table.remove(grates, i)
      else
        p.vy = p.vy + g
        p.x, p.y, p.angle = p.x + p.vx, p.y + p.vy, p.angle + GRATE_SPIN
      end
    end
  end)

  local turn_open = false
  wa.on.turn_start(function(event)
    if turn_open then return end
    turn_open = true
    reducer = {}
    local team = event.worm and event.worm.team
    for _, f in ipairs(fans) do
      if f.team == team and f.turns > 0 then f.turns = f.turns - 1 end
    end
  end)
  wa.on.turn_end(function() turn_open = false end)

  -- 1 to 5 set the force (higher digits are 5); + switches between on its
  -- side (wind) and upright (rising air).
  require("lib/turn_controls").register(ID, {
    choose = function(worm, digit)
      if digit >= 1 then force[worm.id] = math.min(digit, MAX_FORCE) end
    end,
    hint = function(worm)
      return string.format("Fan: force %d, %s\n1-5: force, +: %s", force[worm.id] or MAX_FORCE,
        vertical[worm.id] and "upright" or "on its side", vertical[worm.id] and "on its side" or "upright")
    end,
  })
  wa.on.worm_message(function(worm)
    local id = worm.id
    local pressed = worm.turn and worm.weapon == ID and wa.world.keys().plus_key or false
    if pressed and not plus_held[id] then vertical[id] = not vertical[id] end
    plus_held[id] = pressed
  end, { msgs = { wa.msg.FRAME_FINISH } })

  -- The Tazer's arc destroys a running fan.
  require("lib/electrical").register({
    kind = "fan",
    targets = function()
      local out = {}
      for _, f in ipairs(fans) do
        if active(f) then
          out[#out + 1] = { id = f.a.id, x = art_x(f), y = anchor_y(f) - 1, radius = 14, f = f }
        end
      end
      return out
    end,
    zap = function(obj)
      local f = obj.f
      if not active(f) then return end
      f.health = 1
      if f.grate then knock_grate(f, f.a) end
      f.health = f.health - 12
    end,
    strike = function() end, -- the Lightning Strike recharges nothing yet
  })

  -- A Javelin that stops on a fan hits it, with no push, as PX's does;
  -- missile `id` then pushes it no more by touching it.
  shared.fan_hit = function(x, y, damage, id)
    for _, f in ipairs(fans) do
      if f.alive and not f.sinking and math.abs(x - art_x(f)) < 20 and math.abs(y - (anchor_y(f) - 1)) < 20 then
        if id then f.script_hits[id] = wa.world.frame() end
        hurt(f, f.a, { kind = "bullet", damage = damage })
        return true
      end
    end
    return false
  end

  if wa.on.draw and wa.draw.quad then
    health_label.install()
    local D = wa.depth.OBJECTS
    local QUAD = { points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} } }
    -- A `w` x `h` frame centred on (x, y), its x axis turned to `angle`
    -- radians and mirrored when `flip` is -1.
    local function put(sheet, index, x, y, w, h, angle, flip, color, depth, blend)
      local c, s = wa.math.cos(angle), wa.math.sin(angle)
      local ux, uy = c * w / 2 * flip, s * w / 2 * flip
      local vx, vy = -s * h / 2, c * h / 2
      local p = QUAD.points
      p[1][1], p[1][2] = x - ux - vx, y - uy - vy
      p[2][1], p[2][2] = x + ux - vx, y + uy - vy
      p[3][1], p[3][2] = x + ux + vx, y + uy + vy
      p[4][1], p[4][2] = x - ux + vx, y - uy + vy
      QUAD.sprite, QUAD.frame, QUAD.color = sheet, index, color
      QUAD.depth, QUAD.blend = depth, blend or "alpha"
      wa.draw.quad(QUAD)
    end

    local function tint(f)
      local rgb = f.alliance >= 0 and TEAM_TINT[f.alliance + 1] or NO_TEAM_TINT
      if not f.sinking then return 0xFF000000 | rgb end
      local r = math.floor(((rgb >> 16) & 0xFF) * SUNK_TINT[1])
      local g = math.floor(((rgb >> 8) & 0xFF) * SUNK_TINT[2])
      local b = math.floor((rgb & 0xFF) * SUNK_TINT[3])
      return 0xFF000000 | (r << 16) | (g << 8) | b
    end

    local SIZE = 64 * SCALE
    local function draw_fan(f)
      local ay = anchor_y(f)
      local flip = (not f.vertical and f.side < 0) and -1 or 1
      local body = f.sinking and 0xFF5A5AF0 or nil
      put(ART .. (f.vertical and "body_vertical.png" or "body.png"), 0, art_x(f), ay - 1, SIZE, SIZE, 0, flip, body, D + 3)
      local bx, by = blade_at(f)
      local angle = f.vertical and -HALF_PI or 0
      local blade = f.grate and SIZE or SIZE * 1.25
      if f.speed > 0 then
        put(ART .. "blade.png", math.floor(f.cycle * 4) % 4, bx, by, blade, blade, angle, flip, tint(f), D + 2)
      else
        put(ART .. "blade_idle.png", 0, bx, by, blade, blade, angle, flip, tint(f), D + 2)
      end
      local scale = 32 * SCALE * f.arrow_scale
      local reach = f.arrow_distance
      for _, value in ipairs(f.arrows) do
        local dist = value * 0.1
        local alpha = math.max(0, math.min(255, math.floor(255 * (-4 * dist * (dist - reach)) / (reach * reach))))
        local color = (alpha << 24) | 0xFFC828
        if f.vertical then
          put(ART .. "arrow.png", 0, bx, by - dist, scale * 1.4, scale * 0.8, -HALF_PI, 1, color, D + 1, "add")
        else
          put(ART .. "arrow.png", 0, bx + f.side * dist, by, scale, scale, 0, flip, color, D + 1, "add")
        end
      end
      if f.grate then put(ART .. "grate.png", 0, bx, by, SIZE, SIZE, angle, flip, body, D) end
      if not f.sinking then health_label.draw(f.health, HEALTH, art_x(f), ay - 17, D - 2) end
    end

    wa.on.draw(function()
      for _, f in ipairs(fans) do draw_fan(f) end
      for _, p in ipairs(grates) do
        put(ART .. "grate.png", 0, p.x, p.y, SIZE, SIZE, p.angle, p.flip, nil, D)
      end
    end)
  end
end

return weapon
