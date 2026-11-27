-- Helicopter: a jet pack flown as a helicopter: arrow keys steer, Shift dashes, and a fast landing crashes it.

local weapon = {}

weapon.record = {
  handling = {
    retreat = -1,
  },
  jet_pack = {
    fuel = 255,
  },
}

weapon.defaults = { crate = { type = "utility" }, donor_card = true }

function weapon.definition()
  return require("lib/weapon").merge(weapon.record, {
    copy_from = "stock.jet_pack",
    name = "Helicopter",
    panel_icon = "sprites/helicopter/heli_ico.png",
    sprites = {
      "sprites/helicopter/flying.png", "sprites/helicopter/jumpin.png",
      "sprites/helicopter/dash_bar.png", "sprites/helicopter/dash_frame.png",
      "sprites/helicopter/dash_glow.png", "sprites/helicopter/dash_line.png",
    },
    sounds = {
          "sounds/helicopter/helicopterloop.wav",
          "sounds/helicopter/1.wav", "sounds/helicopter/2.wav", "sounds/helicopter/3.wav",
          "sounds/helicopter/4.wav",
          "sounds/helicopter/oops1.wav", "sounds/helicopter/oops2.wav", "sounds/helicopter/huh.wav",
          "sounds/helicopter/poop.wav", "sounds/helicopter/idiot.wav",
        },
    params = {
      gpu_prefix = "sprites/helicopter/",
      worm_art = { "sprites/helicopter/flying.png", "sprites/helicopter/jumpin.png" },
    },
  })
end

function weapon.setup()
  local shared = require("lib/shared")

  local trunc
  do
  local own_time = require("wf-lib/own_time")

  local HELI_REALISTIC = true -- gravity and wind act on it, at 0.2
  local HELI_EXPLODE_ON_TURN_END = true
  local HELI_DEPTH = wa.depth.FRONT -- in front of worms and terrain
  local HELI_TOP_SPEED = 5 -- pixels a frame an axis: the scheme's default Maximum Jet Pack Speed, as px profiles keep it
  local DASH_FOLLOW = 1 -- pixels a frame: from this speed on, a dash with no arrows goes the way the heli moves
  local COAST_DRAG = 0.0015 -- air drag after a dash, a fraction of the speed a frame per pixel a frame
  local HELI_SLOW = 0.105 -- normal flight slows an unheld axis by 1 / 1.105 a frame
  local DASH_FRAMES = 1.5 -- frames of dash a unit of fuel: the option's 100 (10 here) lasts 15 frames
  local CRATE_POP = 115 -- WA's CratePop

  local helis = {}

  function trunc(v)
    return v >= 0 and math.floor(v) or math.ceil(v)
  end

  local function heli_of(worm)
    local h = helis[worm.id]
    if not h then
      h = { flying = false, launch = false, jumpin = false, jump_phase = 0, frame = 0, ticks = 0 }
      helis[worm.id] = h
    end
    return h
  end

  local function heli_actor(worm, sheet)
    local a = wa.actors.spawn({
      sprite = sheet, x = worm.x, y = worm.y, owner = worm, visibility = worm, on = function() end,
    })
    a:gfx({ glow_of = worm, follow = worm })
    return a
  end

  local function heli_drop_art(h, worm)
    if h.body then h.body:remove(); h.body = nil end
    if h.climb then h.climb:remove(); h.climb = nil end
    worm.body_visible = true
  end

  local HELI_OOPS = {
    [2] = "sounds/helicopter/oops1.wav", [4] = "sounds/helicopter/oops2.wav",
    [6] = "sounds/helicopter/huh.wav", [8] = "sounds/helicopter/poop.wav",
    [10] = "sounds/helicopter/idiot.wav",
  }

  local function heli_crash(worm, h, sx, sy)
    if not h.flying then
      return
    end
    local speed = (math.abs(sy) + math.abs(sx)) / 2
    -- infinite fuel's counter is the fuel used, not what's left: its blast is sized as for 1 left
    local size = trunc(((shared.helicopter_fuel == 0 and 1 or worm.fuel) - 75) / 10 * speed)
    if size < 10 then size = 10 end
    -- how much of that growth with speed the profile wants: 0 none, 100 all of it
    size = trunc(10 + (size - 10) * (shared.helicopter_crash_scale or 0) / 100)
    wa.world.explode({ x = worm.x, y = worm.y, owner = worm, damage = size * 2, id = size })
    worm.gravity = 1
    worm.wind = 0
    local oops = HELI_OOPS[wa.random(1, 10)]
    if oops then wa.sound.play(worm, oops) end
    h.flying, h.dash, h.coast = false, nil, false
    heli_drop_art(h, worm)
  end

  local function push(v, dir)
    local s = -dir * v
    if s > -1 then s = s - 0.2 end
    if s > -4 then s = s - 0.4 end
    if s > -8 then s = s - 0.15 end
    if s > -10 then s = s - 0.05 end
    return -dir * s
  end

  local function dash_options()
    return shared.helicopter_dash or { fuel = 5, speed = 330, steer = 130, refill = 35, cost = 15 }
  end

  local function dash_full()
    return dash_options().fuel * DASH_FRAMES
  end

  local function dash_start(worm, h)
    h.dash = {}
    worm.gravity, worm.wind = 0, 0
    worm:jetpack_steer(true, { speed_limit = false }) -- WA clamps a jet pack to the scheme's top speed
  end

  local function dash_end(worm, h)
    h.dash, h.coast = nil, true
    worm.gravity = HELI_REALISTIC and 0.2 or 0
    worm.wind = HELI_REALISTIC and 0.2 or 0
  end

  -- Near the heli's top speed, the coast after a dash brakes each axis harder and harder:
  -- (top / speed)^8 of normal flight's slowing. It glides on air drag, then eases into
  -- normal flight with no sudden stop, and a tailwind can't keep it going. Held the way it
  -- moves, an axis stops at the top speed, where normal flight's keys hold it.
  local function coast_slow(v, plus, minus)
    local a = math.abs(v)
    if a == 0 then return 0 end
    local held = (v > 0 and plus and not minus) or (v < 0 and minus and not plus)
    if held and a <= HELI_TOP_SPEED then return v end
    local r = math.min(1, HELI_TOP_SPEED / a)
    r = r * r
    r = r * r
    local slowed = v / (1 + HELI_SLOW * r * r)
    if held and math.abs(slowed) < HELI_TOP_SPEED then
      return v > 0 and HELI_TOP_SPEED or -HELI_TOP_SPEED
    end
    return slowed
  end

  -- An arrow's push. In the coast it adds nothing past the top speed the way it pushes:
  -- the scheme's limit is lifted then, and it would hold the heli at 8 pixels a frame.
  local function thrust(v, dir, grip, coast)
    if coast and v * dir >= HELI_TOP_SPEED then return v end
    return v + (push(v, dir) - v) * grip
  end

  -- The dash is normal flight made k times as fast: worked out at 1/k of the speed, the
  -- arrows push and an unheld axis slows as they do in normal flight, at `grip` of their
  -- push and `slow` of the slowing. The whole speed is held to k times the heli's top speed,
  -- so a diagonal is no faster. With no arrow held, it speeds up the way it goes (nearly
  -- still: the way it faces).
  local function dash_fly(vx, vy, k, grip, slow, keys, facing)
    local up, down, left, right = keys.up, keys.down, keys.left, keys.right
    local x, y = vx / k, vy / k
    if not (up or down or left or right) then
      local s = math.sqrt(x * x + y * y)
      local dx, dy = facing, 0
      if s * k >= DASH_FOLLOW then dx, dy = x / s, y / s end
      s = s + (push(s, 1) - s) * grip
      x, y = dx * s, dy * s
    else
      if not up and not down then y = y / (1 + HELI_SLOW * slow) end
      if not left and not right then x = x / (1 + HELI_SLOW * slow) end
      if up and down then y = y / 1.095 end
      if left and right then x = x / 1.095 end
      if up then y = y + (push(y, -1) - y) * grip end
      if down then y = y + (push(y, 1) - y) * grip end
      if left then x = x + (push(x, -1) - x) * grip end
      if right then x = x + (push(x, 1) - x) * grip end
    end
    local s = math.sqrt(x * x + y * y)
    if s > HELI_TOP_SPEED then x, y = x * HELI_TOP_SPEED / s, y * HELI_TOP_SPEED / s end
    return x * k, y * k
  end

  -- How fast the air lines stream back past the heli, in pixels a frame.
  local function flow_speed(speed)
    return math.min(4 + 0.7 * speed, 20)
  end

  local function turn_toward(from, to, step)
    local d = (to - from + 180) % 360 - 180
    if d > step then d = step elseif d < -step then d = -step end
    return (from + d) % 360
  end

  local function heli_frame(worm)
    local h = helis[worm.id]
    local state = worm.state
    if worm.weapon == "px.helicopter" and state == "prefiring" and not (h and h.flying) then
      h = heli_of(worm)
      h.jumpin, h.armed = true, true
      h.jump_phase = h.jump_phase + 0.047 * own_time.frames(worm)
    end
    if h and h.armed and state == "jetpacking" and not h.flying then
      local fuel = shared.helicopter_fuel or 255
      worm.fuel = fuel -- infinite: WA's counter from 0, which it hides until it moves
      worm.gravity = HELI_REALISTIC and 0.2 or 0
      worm:jetpack_steer(true)
      h.flying, h.launch, h.ticks, h.armed = true, true, 0, false
      h.dash, h.coast, h.dash_left, h.worm = nil, false, dash_full(), worm -- dash_left counts frames
      h.dash_empty = false
      h.speed, h.flow = 0, 0
      h.shift_was = wa.world.keys().shift -- a dash needs a fresh press
      h.angle = 0
    elseif h and h.armed and not worm.turn then
      h.armed = false -- the turn ended before it fired
    end
    if not h then
      return
    end
    if h.flying and state ~= "jetpacking" then
      worm:jetpack_steer(false)
      worm.gravity, worm.wind = 1, 0
      h.flying, h.dash, h.coast = false, nil, false
      if state ~= "standing" then
        heli_drop_art(h, worm)
        return
      end
      if h.body then h.body:remove(); h.body = nil end
      h.climb_out, h.jump_phase = true, 1
    end
    if h.flying then
      for i = 1, own_time.frames(worm) do
        local vx, vy = worm.vx, worm.vy
        if vx ~= 0 or vy ~= 0 then
          if h.ticks % 47 == 0 then wa.sound.play(worm, "sounds/helicopter/helicopterloop.wav") end
          local radio = wa.random(1, 200)
          if radio % 20 == 0 and radio <= 80 then
            wa.sound.play(worm, "sounds/helicopter/" .. (radio // 20) .. ".wav")
          end
        end
        h.ticks = h.ticks + 1
        if i == 1 and worm.y >= wa.world.water() then
          heli_crash(worm, h, vx, vy)
          return
        end
        if h.launch then
          h.jump_phase, h.jumpin, h.launch = 0, false, false
          if HELI_REALISTIC then worm.wind = 0.2 end
        end
        local k = worm.keys
        local up, down, left, right = k.up, k.down, k.left, k.right
        local sync = wa.world.keys()
        local shift = sync.shift
        local dash = dash_options()
        if h.dash and (not shift or h.dash_left <= 0) then
          dash_end(worm, h)
        elseif not h.dash and shift and not h.shift_was and h.dash_left > 0 and not h.dash_empty then
          -- each press takes its share of the full bar first, so pressing too often runs it dry
          h.dash_left = math.max(0, h.dash_left - dash_full() * dash.cost / 100)
          if h.dash_left > 0 then
            dash_start(worm, h)
          else
            h.dash_empty = true
          end
        end
        h.shift_was = shift
        h.frame = (h.frame + 1) % 3
        local fuel = worm.fuel
        local burn = wa.world.retreat() == 0
        -- infinite fuel counts what it uses up, as WA's infinite jet pack does
        local used = shared.helicopter_fuel == 0 and -1 or 1
        if burn then fuel = fuel - 0.020 * used end
        if h.dash then
          h.dash_left = math.max(0, h.dash_left - 1)
          if h.dash_left <= 0 then h.dash_empty = true end
          if burn then
            -- each arrow burns as in normal flight
            fuel = fuel - ((up and 0.2 or 0) + (down and 0.020 or 0) + (left and 0.1 or 0) + (right and 0.1 or 0)) * used
          end
          local steer = dash.steer / 100
          vx, vy = dash_fly(vx, vy, dash.speed / 100, steer * (shared.helicopter_acceleration or 1), steer, k, worm.facing)
          local speed = math.sqrt(vx * vx + vy * vy)
          if speed > 0 and math.abs(vx) > 0.2 * speed then worm.facing = vx > 0 and 1 or -1 end
        else
          local full = dash.fuel * DASH_FRAMES
          if h.dash_left < full then
            h.dash_left = math.min(full, h.dash_left + dash.refill / 100)
            -- run dry, the dash waits for the whole bar: then the crate pop an octave up
            if h.dash_left >= full and h.dash_empty then
              h.dash_empty = false
              wa.sound.play(worm, CRATE_POP, { pitch = 12 })
            end
          end
          if h.coast then
            -- past the heli's own top speed, air drag slows it by the square of its speed
            local f = 1 / (1 + COAST_DRAG * math.sqrt(vx * vx + vy * vy)) -- stays above 0 at any speed
            vx, vy = coast_slow(vx * f, right, left), coast_slow(vy * f, down, up)
            -- checked after the slowing, so a tailwind's bit each frame can't hold it past the top speed
            if math.abs(vx) <= HELI_TOP_SPEED and math.abs(vy) <= HELI_TOP_SPEED then
              h.coast = false
              worm:jetpack_steer(true) -- back within the scheme's top speed
            end
          else
            if not up and not down then vy = vy / 1.105 end
            if not left and not right then vx = vx / 1.105 end
            if up and down then vy = vy / 1.095 end
            if left and right then vx = vx / 1.095 end
            for _, pair in ipairs({ { up, right }, { up, left }, { down, right }, { down, left } }) do
              if pair[1] and pair[2] then
                vx, vy = vx * 0.99 * 0.99, vy * 0.99 * 0.99
              end
            end
          end
          -- still the dash's steering until it's back down to its own top speed; the
          -- Acceleration option scales it all (its 100 multiplies by exactly 1)
          local grip = (h.coast and dash.steer / 100 or 1) * (shared.helicopter_acceleration or 1)
          if up then
            if burn then fuel = fuel - 0.2 * used end
            vy = thrust(vy, -1, grip, h.coast)
          end
          if down then
            if burn then fuel = fuel - 0.020 * used end
            vy = thrust(vy, 1, grip, h.coast)
          end
          if left then
            if burn then fuel = fuel - 0.1 * used end
            if not shift then worm.facing = -1 end
            vx = thrust(vx, -1, grip, h.coast)
          end
          if right then
            if burn then fuel = fuel - 0.1 * used end
            if not shift then worm.facing = 1 end
            vx = thrust(vx, 1, grip, h.coast)
          end
        end
        worm.vx, worm.vy, worm.fuel = vx, vy, fuel
        if used > 0 and worm.fuel <= 0.1 then
          heli_crash(worm, h, worm.vx, worm.vy)
          return
        end
      end
      if HELI_EXPLODE_ON_TURN_END and not worm.turn then
        heli_crash(worm, h, worm.vx, worm.vy)
        return
      end
    end
    local f = worm.facing
    if h.flying then
      if h.climb then h.climb:remove(); h.climb = nil end
      h.body = h.body or heli_actor(worm, "sprites/helicopter/flying.png")
      local a = h.body
      a.x, a.y, a.vx, a.vy, a.facing = worm.x, worm.y, 0, 0, f
      a:frame(h.frame)
      local tilt = math.deg(wa.math.sin(worm.vx / 24))
      if h.dash and (worm.vx ~= 0 or worm.vy ~= 0) then
        tilt = math.deg(wa.math.atan(worm.vy, worm.vx)) + (f < 0 and 180 or 0) -- nose into the way it goes
      end
      -- for the air lines: how fast it goes, and how far the air has streamed past it
      h.speed = math.sqrt(worm.vx * worm.vx + worm.vy * worm.vy)
      h.flow = (h.flow + flow_speed(h.speed)) % 100000
      h.angle = turn_toward(h.angle or 0, tilt % 360, 30)
      a:gfx({ angle = h.angle, depth = HELI_DEPTH })
      worm.body_visible = false
    elseif (h.jumpin and state == "prefiring")
        or (h.climb_out and state == "standing" and h.jump_phase > 0) then
      if h.climb_out then h.jump_phase = h.jump_phase - 0.047 * own_time.frames(worm) end
      h.climb = h.climb or heli_actor(worm, "sprites/helicopter/jumpin.png")
      local a = h.climb
      a.x = worm.x + (f > 0 and -11.5 or 12.5)
      a.y, a.vx, a.vy, a.facing = worm.y + 1, 0, 0, f
      a:frame(math.max(0, math.min(math.floor(h.jump_phase * 23), 22)))
      a:gfx({ depth = HELI_DEPTH })
      worm.body_visible = false
    elseif h.body or h.climb then
      h.climb_out = false
      h.jumpin, h.jump_phase = false, 0
      heli_drop_art(h, worm)
    end
  end

  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FRAME_FINISH then
      heli_frame(worm)
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })

  require("lib/weapon_hint").hint("px.helicopter", function()
    if dash_options().fuel > 0 then return "Helicopter\nPress Shift to dash" end
  end)

  if wa.on.contact then
    wa.on.contact(function(worm, other, c)
      local h = helis[worm.id]
      if h and h.flying and other.kind ~= "mine"
          and (math.abs(c.vx) > 1 or math.abs(c.vy) > 1) then
        heli_crash(worm, h, c.vx, c.vy)
      end
    end)
  end

  if wa.on.draw and wa.draw and wa.draw.brush and wa.draw.ribbon then
    local ART = "sprites/helicopter/"
    local bar = wa.draw.brush({ sprite = ART .. "dash_bar.png", blend = "alpha", depth = HELI_DEPTH })
    local frame = wa.draw.brush({ sprite = ART .. "dash_frame.png", blend = "alpha", depth = HELI_DEPTH })
    local glow = wa.draw.brush({ sprite = ART .. "dash_glow.png", blend = "add", depth = HELI_DEPTH })
    local BAR_W, BAR_H, RING = 44, 10, 2 -- dash_frame.png: a grey and a black ring, as stock bars
    local INNER_W, INNER_H = BAR_W - 2 * RING, BAR_H - 2 * RING
    -- the bar's bottom above the heli's centre: clear of its rotor in level flight. It stays
    -- there whatever the tilt (a dash tilts the heli into it, and it draws over the heli),
    -- since following the tilted outline made it jump at every dash and bob with speed
    local BAR_ABOVE = 25

    -- Streamlines hugging the heli, in the flying sprite's frame facing right (x ahead,
    -- y down): each bends round the nose like a U, follows the outline a few pixels out
    -- and runs on past the tail. Streaks of air slide back along them.
    local TOP = { { 34, -19 }, { 20, -21 }, { 0, -22 }, { -20, -22 }, { -38, -21 }, { -46, -16 }, { -54, -18 } }
    local BOTTOM = { { 34, 6 }, { 24, 16 }, { 10, 22 }, { -4, 23 }, { -16, 15 }, { -28, 4 }, { -54, 1 } }
    local NOSE_X, NOSE_Y = 37, 3
    local LINES_A_SIDE, STREAKS, STREAK_POINTS = 5, 4, 5
    local AIR_FROM, AIR_FULL = 7.5, 15 -- pixels a frame: none up to the heli's own top speed, all by 300%

    local function streamline(edge, side, k)
      local gap = 3 + 4 * k
      local pts = {}
      -- the U round the nose: a quadratic curve from just ahead of it out to the outline
      local x0, y0 = NOSE_X + 3 + gap, NOSE_Y + side * gap * 0.25
      local x1, y1 = edge[1][1], edge[1][2] + side * gap
      for i = 0, 5 do
        local t = i / 5
        local u = 1 - t
        pts[#pts + 1] = { u * u * x0 + 2 * u * t * x0 + t * t * x1, u * u * y0 + 2 * u * t * y1 + t * t * y1 }
      end
      for i = 2, #edge do pts[#pts + 1] = { edge[i][1], edge[i][2] + side * gap } end
      pts[#pts + 1] = { edge[#edge][1] - 16 - 6 * k, edge[#edge][2] + side * gap }
      local cum = { 0 }
      for i = 2, #pts do
        local ax, ay = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
        cum[i] = cum[i - 1] + math.sqrt(ax * ax + ay * ay)
      end
      local grey = 255 - 20 * k -- the inner lines white, the outer grey
      return { pts = pts, cum = cum, total = cum[#cum], rgb = grey * 0x10101, k = k }
    end

    local LINES = {}
    for k = 0, LINES_A_SIDE - 1 do
      LINES[#LINES + 1] = streamline(TOP, -1, k)
      LINES[#LINES + 1] = streamline(BOTTOM, 1, k)
    end

    local function along(line, at)
      local pts, cum = line.pts, line.cum
      for i = 2, #pts do
        if at <= cum[i] or i == #pts then
          local t = (at - cum[i - 1]) / (cum[i] - cum[i - 1])
          return pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t, pts[i - 1][2] + (pts[i][2] - pts[i - 1][2]) * t
        end
      end
    end

    local RIBBON = { sprite = ART .. "dash_line.png", blend = "alpha", depth = HELI_DEPTH, points = {} }
    for j = 1, STREAK_POINTS do
      RIBBON.points[j] = { x = 0, y = 0, width = 1.5, color = 0, u = (j - 1) / (STREAK_POINTS - 1) }
    end

    -- More lines, more streaks a line, longer and stronger ones, the faster it goes.
    local function draw_streaks(h, x, y, facing, worm)
      local air = math.max(0, math.min(1, (h.speed - AIR_FROM) / (AIR_FULL - AIR_FROM)))
      if air <= 0 then return end
      local lines, streaks = math.ceil(LINES_A_SIDE * air), 1 + math.ceil((STREAKS - 1) * air)
      local length = math.min(12 + 0.8 * h.speed, 36)
      local flowed = h.flow + flow_speed(h.speed) * wa.draw.fraction()
      local r = math.rad(h.angle or 0)
      local c, s = math.cos(r), math.sin(r)
      local ax, ay, dx, dy = facing * c, facing * s, -s, c -- the sprite's ahead and down on screen
      RIBBON.visibility = worm
      for i, line in ipairs(LINES) do
        if line.k < lines then
          local loop = line.total + length
          local strength = air * (1 - 0.1 * line.k)
          for n = 0, streaks - 1 do
            local start = (flowed + loop * (n / STREAKS + i * 0.37)) % loop - length
            local from, to = math.max(0, start), math.min(line.total, start + length)
            if to - from >= 3 then
              for j = 1, STREAK_POINTS do
                local t = (j - 1) / (STREAK_POINTS - 1)
                local at = from + (to - from) * t
                local fx, fy = along(line, at)
                local fade = math.max(0, math.min(1, at / 10, (line.total - at) / 30))
                local p = RIBBON.points[j]
                p.x = x + ax * fx + dx * fy
                p.y = y + ay * fx + dy * fy
                p.color = (math.floor(230 * strength * fade * math.sin(math.pi * t)) << 24) | line.rgb
              end
              wa.draw.ribbon(RIBBON)
            end
          end
        end
      end
    end

    -- At the heli actor's drawn place: it follows the worm smoothly, the hidden worm doesn't.
    local function draw_heli(h)
      local body, worm = h.body, h.worm
      local x, y = body.x, body.y
      local full = dash_full()
      if full > 0 then
        local left = math.floor(x - BAR_W / 2 + 0.5)
        local top = math.floor(y - BAR_ABOVE - BAR_H + 0.5)
        local cx, cy = left + BAR_W / 2, top + BAR_H / 2
        local w = INNER_W * math.max(0, math.min(1, h.dash_left / full))
        local fx = left + RING + w / 2
        bar:box(cx, cy, INNER_W, INNER_H, 0, 0, 0xE0363E82, worm)
        if w > 0 then
          if h.dash then
            glow:box(fx, cy, w + 12, INNER_H + 12, 0, 0, 0x50FF4A2A, worm)
            bar:box(fx, cy, w, INNER_H, 0, 0, 0xFFFE6A5A, worm)
          elseif h.dash_empty then
            bar:box(fx, cy, w, INNER_H, 0, 0, 0xFFD8282E, worm) -- run dry: red until it's full again
          else
            bar:box(fx, cy, w, INNER_H, 0, 0, 0xFF9C9DFE, worm)
          end
        end
        frame:box(cx, cy, BAR_W, BAR_H, 0, 0, h.dash_empty and 0xFFFF7070 or 0xFFFFFFFF, worm)
      end
      draw_streaks(h, x, y, body.facing, worm)
    end

    wa.on.draw(function()
      for _, h in pairs(helis) do
        if h.flying and h.body and h.dash_left then draw_heli(h) end
      end
    end)
  end
  end
end

function weapon.configure(ctx, spec)
  local fuel = ctx.option("fuel")
  require("lib/shared").helicopter_fuel = fuel
  spec.jet_pack.fuel = math.min(fuel, 255)
  require("lib/shared").helicopter_acceleration = ctx.option("acceleration") / 100
  require("lib/shared").helicopter_crash_scale = ctx.option("crash_speed_scale")
  require("lib/shared").helicopter_dash = {
    fuel = ctx.option("dash_fuel") * 0.1, -- the option's 100 is 10 units of fuel
    speed = ctx.option("dash_speed"),
    steer = ctx.option("dash_steer_factor"),
    refill = ctx.option("dash_refill_factor"),
    cost = ctx.option("dash_use_cost"),
  }
end

return weapon
