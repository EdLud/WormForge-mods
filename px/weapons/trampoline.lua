-- Specialists' Trampoline (PX utility_trampoline_destruct: trampolineDestr.txt):
-- a thrown, breakable trampoline. A worm, missile or mine that lands on it
-- moving is thrown up again and across; it tires after a turn ends, and of
-- endless bouncing.
local weapon = {}
local ART = "sprites/trampoline/"
local SND = "sounds/trampoline/"
local trampolines = {}

-- CTrampolineDestr's own numbers.
local BOUNCE = 7            -- TrampBounce: up speed, plus 1 or 2 by turns
local ACROSS = 3            -- TrampSpX: speed across, toward its far side
local HEALTH = 40
local BREAK_BLAST = 10      -- ExpDamage
local TIRES_AFTER = 250     -- inactive_timer_limit: frames after a turn ends
local LOOP_WINDOW = 125     -- loop_timer_limit
local LOOP_JUMPS = 10       -- loop_jumps_limit: off past twice this
-- PX's ColMask(34, 0, 68x12): its top edge at the object's place. The body
-- here is centred, so the object's place is HALF above the actor's.
local HALF = 6

-- Worm states PX leaves alone (CheckCollisionEx: WS_IDLE, WS_AIMING,
-- WS_WALKING, WS_SETPOWER, the firing ones, WS_TELEPORTING, WS_BLOWTORCH);
-- roping and bungee worms are not thrown either. Every other worm is.
local STAYS = { standing = true, walking = true, ready = true, charging = true,
  prefiring = true, firing = true, fired = true, punching = true, drilling = true,
  teleporting = true, roping = true, bungee = true }

local function damage(s, a, amount)
  if not s.alive or amount <= 0 then return end
  s.health = s.health - amount
  if s.health <= 0 then
    -- Stop accepting hits before the blast can re-enter this callback.
    s.alive = false
    a:explode({ damage = BREAK_BLAST, id = 100 })
    a:despawn()
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
    -- PX's M_FRAME: with a worm on turn it is on unless it tired of looping.
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
      -- An idle worm on it resets its loop count.
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
      local power = ev.blast_damage
      local dx, dy = ev.x - a.x, ev.y - (a.y - HALF)
      -- PX's centre-based quadratic falloff, rather than WA's linear one.
      if power > 0 then
        damage(s, a, math.floor((1 - (dx * dx + dy * dy) / (power * power * 4)) * power))
      end
    else
      damage(s, a, math.max(0, ev.damage or 0))
    end
  end

  -- PX: the worm's x +/- 3, y - 12, thrown 2 across (its facing) and 3 up.
  s.actor = wa.actors.spawn({
    sprite = false, owner = worm, x = worm.x + 3 * side, y = worm.y - 12 + HALF,
    -- An actor with callbacks and no sprite has no gravity unless asked:
    -- PX's trampoline falls, lands and can sink.
    vx = 2 * side, vy = -3, origin = "center", persist = true, gravity = true, drown = true,
    body = { shape = ART .. "body.png", hits = { land = true }, hit_by = "all" },
    on = { frame = frame, contact = contact, hit = hit },
  })
  trampolines[#trampolines + 1] = s
end

-- Project X's Personal Invisibility keeps the thrower invisible.
weapon.defaults = { ends_invisibility = false }

weapon.definition = {
  -- PX's record from the Specialists scheme (the Laser Sight's slot): a
  -- dropped weapon whose firing builds the trampoline instead.
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
  -- PX's M_TURNEND starts its tiring clock; M_TURNBEGIN wakes it again.
  wa.on.turn_end(function()
    for _, s in ipairs(trampolines) do s.tiring = true end
  end)
  wa.on.turn_start(function()
    for i = #trampolines, 1, -1 do
      local s = trampolines[i]
      if s.alive then s.tiring, s.tire_timer, s.active = false, 0, true
      else table.remove(trampolines, i) end
    end
  end)
  wa.on.draw(function()
    local now = wa.world.frame()
    for _, s in ipairs(trampolines) do
      if s.alive and s.actor.id ~= 0 then
        -- The springing art for the frame it throws something.
        local sheet = now <= s.jumped and "jumptramp.png" or "tramp.png"
        -- Drawn 4 pixels lower than the body's top, so its legs stand in the ground.
        local x, y = s.actor.x, s.actor.y - HALF + 4
        wa.draw.quad({ sprite = ART .. sheet, frame = 0, depth = wa.depth.OBJECTS,
          points = { { x - 35, y - 16 }, { x + 35, y - 16 }, { x + 35, y + 16 }, { x - 35, y + 16 } } })
      end
    end
  end)
end

return weapon
