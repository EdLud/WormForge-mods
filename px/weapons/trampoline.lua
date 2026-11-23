-- Trampoline: a thrown, breakable trampoline that throws worms, missiles and mines back up.

local weapon = {}
local ART = "sprites/trampoline/"
local SND = "sounds/trampoline/"
local trampolines = {}

local BOUNCE = 7 -- TrampBounce: up speed, plus 1 or 2 by turns
local ACROSS = 3 -- TrampSpX: speed across, toward its far side
local HEALTH = 40
local BREAK_BLAST = 10 -- ExpDamage
local TIRES_AFTER = 250 -- inactive_timer_limit: frames after a turn ends
local LOOP_WINDOW = 125 -- loop_timer_limit
local LOOP_JUMPS = 10 -- loop_jumps_limit: off past twice this
local HALF = 6

local STAYS = { standing = true, walking = true, ready = true, charging = true,
  prefiring = true, firing = true, fired = true, punching = true, drilling = true,
  teleporting = true, roping = true, bungee = true }

local function damage(s, a, amount)
  if not s.alive or amount <= 0 then return end
  s.health = s.health - amount
  if s.health <= 0 then
    s.alive = false
    a:explode({ damage = BREAK_BLAST, id = 100 })
    a:remove()
  end
end

local function place(fire)
  local worm = fire.worm
  local side = worm.facing > 0 and 1 or -1
  local s = { alive = true, health = HEALTH, active = true, tired = true,
    tiring = false, tire_timer = 0, looping = false, loop_timer = 0, loop_jumps = 0,
    lift = 0, jumped = -1 }
  local current_worm = require("lib/shared").current_worm

  local function frame(a)
    if not s.alive then return end
    if current_worm() and s.tired then s.active = true
    elseif not s.tired then s.active = false end
    if s.tiring then
      s.tire_timer = s.tire_timer + 1
      if s.tire_timer > TIRES_AFTER then
        s.active, s.tire_timer, s.tiring = false, 0, false
      end
    end
    if s.looping then
      s.loop_timer = s.loop_timer + 1
      if s.loop_jumps > LOOP_JUMPS * 2 then
        s.tired, s.looping = false, false
      end
      if s.loop_timer > LOOP_WINDOW then
        s.loop_jumps, s.looping = 0, false
      end
    end
  end

  local function contact(a, ev)
    local other = ev.other
    if not s.alive or type(other) ~= "userdata" and type(other) ~= "table" then return end
    local kind = other.kind
    if kind ~= "worm" and kind ~= "missile" and kind ~= "mine" then return end
    if kind == "worm" then
      local state = other.state
      if state == "standing" or state == "walking" or state == "ready" then
        s.tired, s.loop_jumps, s.loop_timer = true, 0, 0
      end
      if STAYS[state] then return end
    end
    s.looping, s.loop_jumps, s.loop_timer = true, s.loop_jumps + 1, 0
    s.jumped = wa.world.frame()
    wa.sound.play(a, SND .. (wa.random(1, 2) == 1 and "bananaimpact.wav" or "wormspring.wav"))
    s.lift = s.lift % 2 + 1
    if s.active then
      other.vy = -(BOUNCE + s.lift)
      other.vx = other.x <= a.x and ACROSS or -ACROSS
    else
      other.vy = 0
    end
  end

  local function hit(a, ev)
    if ev.kind == "blast" then
      local power = ev.power
      local dx, dy = ev.x - a.x, ev.y - (a.y - HALF)
      if power > 0 then
        damage(s, a, math.floor((1 - (dx * dx + dy * dy) / (power * power * 4)) * power))
      end
    else
      damage(s, a, math.max(0, ev.damage or 0))
    end
  end

  s.actor = wa.actors.spawn({
    sprite = false, owner = worm, x = worm.x + 3 * side, y = worm.y - 12 + HALF,
    vx = 2 * side, vy = -3, origin = "center", persist = true, gravity = 1, drown = true,
    body = { shape = ART .. "body.png", hits = { land = true }, hit_by = "all" },
    on = { frame = frame, touched = contact, hit = hit },
  })
  trampolines[#trampolines + 1] = s
end

weapon.defaults = { ends_invisibility = false }

weapon.definition = {
  wep = "weps/trampoline.wep",
  name = "Trampoline",
  panel_icon = ART .. "tramp_ico.png",
  worm_sprites = {
    weaponlnk = ART .. "hold.png", weaponlnku = ART .. "holdu.png", weaponlnkd = ART .. "holdd.png",
    wthrow = ART .. "pick.png", wthrowu = ART .. "picku.png", wthrowd = ART .. "pickd.png",
  },
  sprites = { ART .. "tramp.png", ART .. "jumptramp.png" },
  sounds = { SND .. "bananaimpact.wav", SND .. "wormspring.wav" },
  params = { gpu_prefix = ART },
  on_fire = place,
}

function weapon.setup()
  wa.on.turn_end(function()
    for _, s in ipairs(trampolines) do s.tiring = true end
  end)
  wa.on.turn_start(function()
    for i = #trampolines, 1, -1 do
      local s = trampolines[i]
      if s.alive then
        s.tiring, s.tire_timer, s.active = false, 0, true
        -- A give-up ends here too: in PX a worm standing on it ends it, but a
        -- standing worm sends no touch here, so the trampoline stayed dead.
        s.tired, s.looping, s.loop_jumps, s.loop_timer = true, false, 0, 0
      else table.remove(trampolines, i) end
    end
  end)
  local TRAMP = wa.draw.brush{ sprite = ART .. "tramp.png", depth = wa.depth.OBJECTS }
  local JUMPED = wa.draw.brush{ sprite = ART .. "jumptramp.png", depth = wa.depth.OBJECTS }
  local health_label = require("lib/sentry_health")
  health_label.install()
  wa.on.draw(function()
    local now = wa.world.frame()
    for _, s in ipairs(trampolines) do
      local a = s.actor
      if s.alive and a.alive then
        local brush = now <= s.jumped and JUMPED or TRAMP
        brush:box(a.x, a.y - HALF + 4, 70, 32)
        if not a:in_water() then
          health_label.draw(s.health, HEALTH, a.x, a.y - HALF, wa.depth.OBJECTS - 2)
        end
      end
    end
  end)
end

return weapon
