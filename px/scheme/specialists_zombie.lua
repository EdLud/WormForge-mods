-- The Soldier's zombie: Project X's script_random_zombies (zomb.txt,
-- FirePunch.txt, wormanim.txt), narrowed to the Soldier by Specialists'
-- script_overrides. Behaviour, not PX's object loops: see
-- docs/px-reverse-engineering.md, "Specialists phase 5".
--
-- A Soldier brought to 0 HP, not drowning, comes back once with 100 HP as a
-- zombie: WA's turns and Tab pass it over (worm.selectable), and while a
-- turn's clock runs it goes for the worm being played, any team's: it walks
-- to it and punches, or leaps at it from further off. A team whose living
-- worms are all zombies is out. Lightning makes a zombie a Soldier again,
-- which may turn once more.
local zombie = {}

local PUNCH = "sprites/specialists/zombie_punch.png"           -- 3 frames
local PUNCH_STOP = "sprites/specialists/zombie_punch_stop.png" -- 13 frames
zombie.sprites = { PUNCH, PUNCH_STOP }

local HP = 100
local PUNCH_FRAMES = 30       -- FirePunchTimer
local STOP_FRAMES = 22        -- punchstop at AnimSpeed 1/22
local ATTACK_COOLDOWN = 60
local DAMAGE_COOLDOWN = 60
local PUNCH_DAMAGE = 30
local PUNCH_PUSH_X, PUNCH_PUSH_Y = 4, -9
-- PX's punch is speeds and a hit, no sound. WA's own Fire Punch hits with
-- FirePunchImpact (sound 101, pushed with its hit at 0x5185FA): the same here.
local PUNCH_SOUND = 101
local HOP_Y = -6              -- PunchIt: SpX 0, SpY -6
local LEAP_RANGE = 400
-- ApplyMask(4, x, y - 7) every punch frame. PX's mask 4 isn't documented
-- anywhere we have; a worm-sized round hole stands in for it.
local DIG_RADIUS = 10

-- The worm states PX lets punch (WS_IDLE, WS_JUMP, WS_WALKING, WS_SLIDING,
-- WS_JUMPPREPARE).
local CAN_PUNCH = { standing = true, walking = true, sliding = true, jumping = true, jump_prepare = true }

-- is_soldier(worm), soldier_name: from the Specialists rules.
function zombie.install(is_soldier, soldier_name)
  local shared = require("lib/shared")
  local zombies, spent = {}, {}         -- by worm id; spent: may not turn again
  local turning = {}                    -- a lethal hit was cut to 1 HP
  local attack_cd, damage_cd = {}, {}
  local punch, stop = {}, {}            -- frames left of the punch, of its recovery
  local out = {}                        -- zombies of a team that is out
  local target                          -- the worm being played
  local last_frame, last_clock, running

  function zombie.is_zombie(worm) return zombies[worm.id] == true end

  local function alive(worm)
    return worm.hp > 0 and worm.state ~= "dying" and worm.state ~= "drowning" and worm.state ~= "dead"
  end

  local function turn(worm)
    zombies[worm.id], spent[worm.id], turning[worm.id] = true, true, nil
    if worm.hp <= 0 then
      worm:heal(HP, { from_zero = true })
    elseif worm.hp < HP then
      worm:heal(HP - worm.hp)
    end
    worm.selectable = false
    worm.name = "Zombie"
    wa.log("Specialists: worm " .. worm.id .. " comes back as a zombie")
  end

  -- Lightning (PX's LightningHit override): a zombie is a Soldier again, no
  -- HP added, and may turn once more. True: the strike adds no health.
  shared.lightning_restores_worm = function(worm)
    if not zombies[worm.id] or out[worm.id] then return false end
    zombies[worm.id], spent[worm.id] = nil, nil
    punch[worm.id], stop[worm.id] = nil, nil
    worm.selectable = true
    worm.body_visible = true
    worm.name = soldier_name
    wa.log("Specialists: Lightning restores worm " .. worm.id)
    return true
  end

  -- A hit that would kill a Soldier who may still turn leaves it 1 HP and
  -- its push; it turns on its next frame. Fall damage has no hurt message:
  -- that Soldier is raised from 0 HP instead (worm:heal from_zero).
  wa.on.hurt(function(hit)
    local worm = hit.worm
    if hit.phase ~= "pre" or not worm or zombies[worm.id] or spent[worm.id] then return end
    if not is_soldier(worm) or not alive(worm) then return end
    if hit.kind == "percent" or hit.kind == "poison" then return end
    if hit.amount and hit.amount >= worm.hp then
      hit.amount = worm.hp - 1
      turning[worm.id] = true
    end
  end)

  wa.on.turn_start(function(event) target = event.worm; last_clock, running = nil, false end)
  wa.on.turn_end(function() target, last_clock, running = nil, nil, false end)

  local function team_out_check(worms)
    local humans, theirs = {}, {}
    for _, worm in ipairs(worms) do
      if alive(worm) then
        if zombies[worm.id] then
          theirs[#theirs + 1] = worm
        else
          humans[worm.team] = true
        end
      end
    end
    for _, worm in ipairs(theirs) do
      if not humans[worm.team] then
        -- zomb.txt's destroyTeam: health to 0; WA ends them with the turn.
        -- WA's accounting takes one hit per worm a frame: tried again
        -- each frame until it has.
        worm:hurt({ amount = worm.hp, react = false })
        if not out[worm.id] then
          wa.log("Specialists: team " .. worm.team .. " has only zombies left")
        end
        out[worm.id] = true
      end
    end
  end

  -- Once a frame: cooldowns, the turn clock, teams out.
  local function each_frame()
    for _, t in ipairs({ attack_cd, damage_cd }) do
      for _, id in ipairs(wa.sorted(t)) do
        t[id] = t[id] > 1 and t[id] - 1 or nil
      end
    end
    local clock = target and wa.world.turn_clock()
    running = clock ~= nil and last_clock ~= nil and clock < last_clock
    last_clock = clock
    team_out_check(wa.worms.all())
  end

  local function face(worm, x) worm.facing = worm.x < x and 1 or -1 end

  local function leap(z, t)
    local dx, dy = t.x - z.x, t.y - z.y
    local l = math.sqrt(dx * dx + dy * dy)
    if l > LEAP_RANGE or wa.land.trace(z.x, z.y, t.x, t.y) then return end
    -- PX's MakeLeap: an arc reaching the target in l / 10 + 1 frames
    -- (SolveBallistic), its force plus 0..63/96 at random, less 0.1.
    local frames = l / 10 + 1
    local g = wa.world.gravity() * t.gravity
    local rx = dx / frames
    local ry = (2 * dy - g * frames * frames) / (2 * frames)
    local power = math.sqrt(rx * rx + ry * ry)
    if power <= 0 then return end
    local force = power - 0.1 + wa.random(0, 63) / 96
    face(z, t.x)
    z:release(rx / power * force, ry / power * force)
  end

  local function act(z)
    local t = target
    if not running or not t or t.id == z.id or zombies[t.id] or not alive(t) then return end
    if t.invisibility then return end
    local x, y, tx, ty = z.x, z.y, t.x, t.y
    if x < tx + 150 and x > tx - 150 and y > ty - 90 and y < ty + 90 then
      if x <= tx + 20 and x >= tx - 20 and y > ty - 12 and y < ty + 100
        and not attack_cd[z.id] and CAN_PUNCH[z.state] then
        face(z, tx)
        attack_cd[z.id] = ATTACK_COOLDOWN
        punch[z.id], stop[z.id] = PUNCH_FRAMES, nil
        z.body_visible = false
        z:release(0, HOP_Y)
      end
      if x < tx + 20 and x > tx - 20 and y > ty - 12 and y < ty + 90 then return end
      if z.state == "standing" or z.state == "walking" then
        if x > tx then z:input({ key = "left" }) elseif x < tx then z:input({ key = "right" }) end
      end
    elseif z.state == "standing" then
      leap(z, t)
    end
  end

  -- FirePunch.txt: every frame of the punch, each other worm in reach
  -- (x -4..+20 ahead, y -25..+12) takes 30 and a push, once a second at most.
  local function punching(z, worms)
    local left = punch[z.id]
    if not left then return end
    if left > 1 then
      punch[z.id] = left - 1
    else
      punch[z.id], stop[z.id] = nil, STOP_FRAMES
    end
    wa.land.cut({ x = z.x, y = z.y - 7, shape = "circle", radius = DIG_RADIUS })
    local f = z.facing >= 0 and 1 or -1
    for _, w in ipairs(worms) do
      if w.id ~= z.id and alive(w) and not damage_cd[w.id] then
        local ahead = (w.x - z.x) * f
        if ahead >= -4 and ahead <= 20 and w.y <= z.y + 12 and w.y >= z.y - 25 then
          damage_cd[w.id] = DAMAGE_COOLDOWN
          w:hurt({ amount = PUNCH_DAMAGE, vx = PUNCH_PUSH_X * f, vy = PUNCH_PUSH_Y })
          wa.sound.play(w, PUNCH_SOUND)
        end
      end
    end
  end

  wa.on.worm_message(function(worm)
    local frame = wa.world.frame()
    if frame ~= last_frame then
      last_frame = frame
      each_frame()
    end
    if worm.state == "drowning" then spent[worm.id] = true end
    if not zombies[worm.id] then
      if is_soldier(worm) and not spent[worm.id] and worm.state ~= "drowning"
        and (turning[worm.id] or worm.hp <= 0) and worm.state ~= "dying" and worm.state ~= "dead" then
        turn(worm)
      end
      return
    end
    if out[worm.id] or not alive(worm) then return end
    if punch[worm.id] then
      punching(worm, wa.worms.all())
    elseif stop[worm.id] then
      stop[worm.id] = stop[worm.id] > 1 and stop[worm.id] - 1 or nil
      if not stop[worm.id] then worm.body_visible = true end
    end
    act(worm)
  end, { msgs = { wa.msg.FRAME_FINISH } })

  -- The punch replaces the body (wormanim.txt): PUNCH while it lasts, then
  -- PUNCH_STOP once through. The art faces left.
  wa.on.draw(function()
    for _, worm in ipairs(wa.worms.all()) do
      local frame, sprite
      if punch[worm.id] then
        sprite, frame = PUNCH, math.floor((PUNCH_FRAMES - punch[worm.id]) / 10) % 3
      elseif stop[worm.id] then
        sprite, frame = PUNCH_STOP, math.min(12, math.floor((STOP_FRAMES - stop[worm.id]) * 13 / STOP_FRAMES))
      end
      if sprite then
        local x, y, s = worm.x, worm.y, worm.facing >= 0 and 30 or -30
        wa.draw.quad({ points = { {x+s,y-30}, {x-s,y-30}, {x-s,y+30}, {x+s,y+30} },
          sprite = sprite, frame = frame, visibility = worm, depth = wa.depth.WORMS })
      end
    end
  end)
end

return zombie
