-- Portal Gun: fires two portals; worms and objects pass from one to the other.

local weapon = {}

weapon.record = {
  fires = {
    subtype = 3,
  },
  handling = {
    ends_turn = false,
  },
}

weapon.defaults = {
  airborne = true,
}

function weapon.definition()
  local shared = require("lib/shared")
  local fires = shared.fires
  return require("lib/weapon").merge(weapon.record, {
    wep = "weps/scales_of_justice.wep",
    panel_icon = "sprites/portal_gun/icon.png",
    worm_sprites = {
          weaponlnk = "sprites/portal_gun/portal_gun_normal.png",
          weaponlnku = "sprites/portal_gun/portal_gun_up.png",
          weaponlnkd = "sprites/portal_gun/portal_gun_down.png",
          wthrow = "sprites/portal_gun/portal_gun_link_normal.png",
          wthrowu = "sprites/portal_gun/portal_gun_link_up.png",
          wthrowd = "sprites/portal_gun/portal_gun_link_down.png",
        },
    sprites = {
          "sprites/portal_gun/portal_ball.png", "sprites/portal_gun/portal_orange.png",
          "sprites/portal_gun/portal_blue.png", "sprites/portal_gun/portal_glow.png",
          "sprites/portal_gun/portal_gun_glow.png",
          "sprites/portal_gun/lightning_glow.png", "sprites/portal_gun/portal_black_mask.png",
          "sprites/portal_gun/crosshair_orange.png", "sprites/portal_gun/crosshair_blue.png",
        },
    -- Its own crosshair in the next shot's colour, in place of WA's.
    crosshair = false,
    sounds = { "sounds/portal_gun_shoot.wav", "sounds/portal_gun_hit.wav", "sounds/portal_gun_failhit.wav",
          "sounds/portal_active.wav", "sounds/portal_inactive.wav", "sounds/portal_teleport.wav" },
    params = { gpu_prefix = "sprites/portal_gun/" },
    on_fire = function(fire) fires.portal_gun(fire) end,
  })
end

function weapon.configure(ctx)
  local shared = require("lib/shared")
  -- The crosshair in flight: only with Mid-air aim on, for a gun that fires there.
  shared.portal_mid_air_aim = ctx.data.airborne ~= false and ctx.option("mid_air_aim") ~= false
end

function weapon.setup()
  local shared = require("lib/shared")
  local Portals = require("lib/portals")
  local Effects = require("lib/portal_effects")
  local ID, ART = "px.portal_gun", "sprites/portal_gun/"
  local SPEED = 35
  local chosen, held, half_used = {}, {}, {}
  local bolts, effects = {}, Effects.new()
  local ticking = false -- portals and effects run from the first shot on
  local colours = { 0xFFDF6400, 0xFF003FEF }
  local team_colours = { 0xD21400, 0x0014DC, 0x00DC00, 0xFADC00, 0xDC00DC, 0x00E6E6 }
  local function sound(name, worm) wa.sound.play(worm, "sounds/" .. name .. ".wav") end
  local network = Portals.new({ grace = 0, on_transport = function(body, entry)
    effects:transport(entry)
    if (body.kind or "worm") == "worm" then sound("portal_teleport", body) end
  end })
  shared.portals = network

  local function tick()
    network:tick()
    effects:tick(wa.world.gravity())
    for _, group in ipairs(wa.sorted(network.pairs)) do
      local pair = network.pairs[group]
      if pair.active and pair[1] and pair[2] and network.age % 500 ~= 0 then
        for colour = 1,2 do effects:ambient(pair[colour]) end
      end
    end
    if network.age % 150 == 0 then
      local alive = {}
      for _, worm in ipairs(wa.worms.all()) do alive["worm:" .. worm.id] = true end
      for _, list in ipairs({wa.missiles, wa.mines, wa.crates, wa.oil, wa.graves, wa.arrows}) do
        for _, body in ipairs(list.all()) do alive[body.id] = true end
      end
      if shared.portal_bowling_balls then
        for _, body in ipairs(shared.portal_bowling_balls()) do alive["actor:" .. body.id] = true end
      end
      for _, key in ipairs(wa.sorted(network.last_exit)) do
        if not alive[key] then network.last_exit[key] = nil end
      end
    end
  end
  wa.on.frame(function()
    if ticking then tick() end
  end)

  local function supported(x, y)
    for _, d in ipairs({ {-15,-15}, {15,15}, {-15,15}, {15,-15} }) do
      local hit = wa.land.trace(x, y, x + d[1], y + d[2])
      if hit and hit.hit then return true end
    end
    return false
  end
  local function shooter(b)
    for _, w in ipairs(wa.worms.all()) do if w.id == b.worm_id then return w end end
  end
  local function place(b, hit)
    if hit.y >= wa.world.water() or not supported(hit.x, hit.y) then
      effects:impact(hit.x, hit.y, true)
      sound("portal_gun_failhit", shooter(b))
      return false
    end
    local p, fresh = network:place(b.team, b.colour, hit.x, hit.y, hit.nx, hit.ny, b.team_colour)
    if not p then effects:impact(hit.x, hit.y, true); sound("portal_gun_failhit", shooter(b)); return false end
    if fresh then chosen[b.team] = 3 - b.colour end
    sound("portal_gun_hit", shooter(b))
    effects:impact(hit.x, hit.y, false)
    if half_used[b.worm_id] then
      half_used[b.worm_id] = nil
      local worm = shooter(b)
      if worm then worm:ammo(ID, -1) end
    else half_used[b.worm_id] = true end
    return true
  end
  local function remove(b)
    bolts[b.id] = nil
    b.a:remove()
  end
  local function bolt_frame(b)
    b.age = b.age + 1
    local size = wa.world.size()
    if b.x < 0 or b.x > size.w or b.y < -size.h then b.vy = b.vy + wa.world.gravity() end
    local hit = wa.world.trace({ x0 = b.x, y0 = b.y, x1 = b.x + b.vx, y1 = b.y + b.vy,
      with = {"terrain"}, radius = 0 })
    if hit and hit.hit then
      place(b, hit)
      remove(b)
      return
    end
    b.x, b.y = b.x + b.vx, b.y + b.vy
    if b.y >= wa.world.water() or b.age > 600 or math.abs(b.x) > 32000 or math.abs(b.y) > 32000 then
      remove(b); return
    end
    b.a.x, b.a.y = b.x, b.y
    b.a:frame((b.age // 2) % 20)
    b.a:gfx({ scale = 0.12, tint = colours[b.colour] & 0xFFFFFF, depth = wa.depth.OBJECTS })
    effects:trail(b.x, b.y, b.colour)
  end
  -- The aim the shot takes, 0 down to 1 up: the aim target, the same on
  -- every machine. `worm.aim` eases toward it as the crosshair draws.
  local function ground_aim(worm) return (worm.aim_target + 90) / 180 end
  -- The arrows held, as an aim: Up+side 0.75, Down+side 0.175, Left and
  -- Right as forward.
  local function air_aim(worm, keys)
    if (keys.left or keys.right) and keys.up then return 0.75 end
    if (keys.left or keys.right) and keys.down then return 0.175 end
    if keys.left or keys.right then return 0.5 end
    if keys.down then return 0 end
    if keys.up then return 1 end
    return ground_aim(worm)
  end

  -- Mid-air aim: in flight the worm keeps a crosshair, and each new arrow
  -- press re-aims it (Core utilities' ExTurnSide turns the worm). Letting go
  -- of the keys keeps the aim. Off, a shot takes the arrows held at Space.
  local IN_FLIGHT = { jump_prepare = true, jumping = true, jump_falling = true,
    falling = true, tumbling = true, hit = true, blasted = true }
  local flights = {} -- [worm id] = { worm, aim, last frame's arrows }
  local function fly(worm, keys)
    local f = flights[worm.id]
    if not f then
      -- Keys already down (walking into the jump) are no press.
      f = { aim = ground_aim(worm) }
      flights[worm.id] = f
    elseif (keys.up and not f.up) or (keys.down and not f.down)
        or (keys.left and not f.left) or (keys.right and not f.right) then
      f.aim = air_aim(worm, keys)
    end
    f.up, f.down, f.left, f.right = keys.up, keys.down, keys.left, keys.right
    return f
  end
  local function land(id) flights[id] = nil end
  -- The colour the next shot takes: the team's, Ctrl or Alt for the other.
  local function shot_colour(worm, keys)
    local colour = chosen[worm.team] or 1
    if keys.ctrl or keys.alt then colour = 3 - colour end
    return colour
  end

  shared.fires.portal_gun = function(fire)
    local worm, keys = fire.worm, wa.world.keys()
    ticking = true
    local colour = shot_colour(worm, keys)
    local aim = ground_aim(worm)
    if fire.airborne then
      aim = shared.portal_mid_air_aim ~= false and fly(worm, keys).aim or air_aim(worm, keys)
    end
    local angle = (1 - aim) * math.pi
    local dx, dy = wa.math.sin(angle) * worm.facing, -wa.math.cos(angle)
    local power = fire.power or 1
    local b = { x = worm.x + dx, y = worm.y + dy,
      vx = (dx * SPEED * power), vy = (dy * SPEED * power),
      worm_id = worm.id, team = worm.team, team_colour = team_colours[worm.alliance + 1],
      colour = colour, age = 0 }
    if not fire.airborne then worm:ammo(ID, 1) end
    local a = wa.actors.spawn({ sprite = ART .. "portal_ball.png", x = b.x, y = b.y,
      owner = worm, on = { frame = function() bolt_frame(b) end } })
    b.a, b.id = a, a.id
    a:gfx({ scale = 0.12, tint = colours[colour] & 0xFFFFFF, depth = wa.depth.OBJECTS })
    bolts[b.id] = b
    sound("portal_gun_shoot", worm)
  end

  wa.on.body_move(function(body) if next(network.pairs) then network:move(body) end end,
    { kinds = { "worm", "missile", "mine", "crate", "oil", "grave", "arrow" } })
  wa.on.worm_message(function(worm)
    local id = worm.id
    if not worm.turn then land(id); return end
    local keys, team = wa.world.keys(), worm.team
    if shared.portal_mid_air_aim ~= false and worm.weapon == ID and IN_FLIGHT[worm.state] then
      fly(worm, keys)
    else
      land(id)
    end
    -- Last frame's keys, kept in one table a worm.
    local old = held[id]
    if not old then old = {}; held[id] = old end
    if keys.pause_key and not old.pause_key then
      local pair = network.pairs[team]
      if pair then
        network:active(team, not pair.active)
        sound(pair.active and "portal_active" or "portal_inactive", worm)
      end
    end
    if worm.weapon == ID then
      if keys.minus_key and not old.minus_key then chosen[team] = 1 end
      if keys.plus_key and not old.plus_key then chosen[team] = 3 - (chosen[team] or 1) end
    end
    old.portal, old.plus_key, old.minus_key, old.pause_key = worm.weapon == ID, keys.plus_key, keys.minus_key, keys.pause_key
  end, { msgs = { wa.msg.FRAME_FINISH } })
  wa.on.turn_start(function() flights = {}; network:turn_start(); held = {} end)
  wa.on.turn_end(function() flights = {}; network:turn_end() end)

  require("lib/weapon_hint").register(ID, function(worm)
    return "Portal Gun: " .. ((chosen[worm.team] or 1) == 1 and "ORANGE" or "BLUE")
      .. "\n+: the other colour, -: orange\nCtrl/Alt: this shot in the other colour\nPause: toggle"
  end)

  if wa.on.draw then
    local tip, tip_frame = Effects.new(), nil
    -- The crosshair, on the ground and in flight, where WA's sits: 94 pixels
    -- out along the aim (WA's aim starts 14 out, 0x51CA90, and the cursor is
    -- 80 past that), turning half a circle as the aim sweeps from down to up
    -- and back (DrawAimCursor 0x51D680).
    local CROSSHAIR = 94
    local CROSSHAIRS = { "crosshair_orange.png", "crosshair_blue.png" }
    -- A brush per sheet, blend and depth, made at its first box: the
    -- portals and their sparks draw every frame and make no tables.
    local brushes = {}
    local function quad(sprite, x, y, w, h, angle, colour, blend, depth, frame, visibility)
      blend, depth = blend or "alpha", depth or wa.depth.OBJECTS
      local by_sheet = brushes[sprite]
      if not by_sheet then by_sheet = {}; brushes[sprite] = by_sheet end
      local key = depth * 2 + (blend == "add" and 1 or 0)
      local brush = by_sheet[key]
      if not brush then
        brush = wa.draw.brush{ sprite = ART .. sprite, blend = blend, depth = depth }
        by_sheet[key] = brush
      end
      brush:box(x, y, w, h, angle or 0, frame or 0, colour, visibility)
    end
    -- The crosshair as a portal burns: the shot colour's fire in WA's
    -- crosshair form, a second copy turning against it, a breathing halo,
    -- and the portals' rising sparks (`step`). Drawn added, so each colour
    -- has its own strength and sparks a frame: orange burns hotter.
    local GLOW = { 0.6, 0.85 } -- orange, blue
    local SPARKS = { 0.3, 0.45 }
    local sparks = 0
    local function draw_crosshair(worm, x, y, aim, colour, step)
      local now = wa.world.frame() + wa.draw.fraction()
      local turn = -aim * math.pi * worm.facing -- half a circle from down to up: an X at 45 degrees
      local breath = 0.9 + 0.1 * math.sin(now * 0.21)
      local glow = GLOW[colour]
      local halo = (math.floor(0x70 * glow) << 24) | (colours[colour] & 0xFFFFFF)
      quad("lightning_glow.png", x, y, 90 * breath, 90 * breath, 0, halo, "add", wa.depth.EFFECTS, 0, worm)
      local sheet = CROSSHAIRS[colour]
      local size = 40 * (1.08 + 0.05 * math.sin(now * 0.33))
      quad(sheet, x, y, size, size, turn - now * 0.06, (math.floor(0x80 * glow) << 24) | 0xFFFFFF, "add",
        wa.depth.EFFECTS, 0, worm)
      quad(sheet, x, y, 40, 40, turn, (math.floor(0xFF * glow) << 24) | 0xFFFFFF, "add", wa.depth.EFFECTS, 0, worm)
      if step then
        sparks = sparks + SPARKS[colour]
        if sparks >= 1 then
          sparks = sparks - 1
          tip:ambient({ x = x, y = y, colour = colour })
        end
      end
    end
    wa.on.draw(function()
      -- Drawing only, so any order: it decides which of two portals that
      -- overlap is on top, on this screen.
      for _, pair in pairs(network.pairs) do
        for colour = 1, 2 do
          local p = pair[colour]
          if p then
            local angle = math.pi / 2 - wa.math.atan(p.nx, p.ny)
            quad(colour == 1 and "portal_orange.png" or "portal_blue.png", p.draw_x, p.draw_y,
              40, 100, angle, 0xFFFFFFFF, "add")
            quad("portal_black_mask.png", p.draw_x - (p.x-p.draw_x)*2, p.draw_y - (p.y-p.draw_y)*2,
              12.5, 12.5, 0, (135 << 24) | (p.team_colour or 0xFFFFFF), "alpha",
              wa.depth.OBJECTS - 1, (network.age // 50) % 2)
          end
        end
      end
      effects:draw(quad)
      local worm = shared.current_worm()
      local now = wa.world.frame()
      local step = now ~= tip_frame
      tip_frame = now
      if step then tip:tick(wa.world.gravity()) end
      local flight = worm and flights[worm.id]
      local holding = worm and worm.weapon == ID
      if flight then
        local angle = (1 - flight.aim) * math.pi
        local x, y = worm.x + math.sin(angle) * worm.facing * CROSSHAIR, worm.y - math.cos(angle) * CROSSHAIR
        draw_crosshair(worm, x, y, flight.aim, shot_colour(worm, wa.world.keys()), step)
      end
      if holding and worm.aiming then
        local colour = shot_colour(worm, wa.world.keys())
        local angle = (1 - worm.aim) * math.pi
        local dx, dy = math.sin(angle) * worm.facing, -math.cos(angle)
        quad("portal_gun_glow.png", worm.x + dx * 18, worm.y + dy * 18, 80, 80,
          math.atan(dy, dx), (100 << 24) | (colours[colour] & 0xFFFFFF), "add", 0x000CFFFF)
        if step then tip:muzzle(worm.x + dx * 20, worm.y + dy * 20, colour, dx, dy) end
        draw_crosshair(worm, worm.x + dx * CROSSHAIR, worm.y + dy * CROSSHAIR, worm.aim, colour, step)
      end
      tip:draw(quad)
    end)
  end
  shared.portal_air_aim = air_aim
end

return weapon
