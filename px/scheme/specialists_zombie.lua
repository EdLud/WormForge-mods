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

local HP = 100
local NAME = "Zombie"
-- PX's RenderWorm colours a zombie with SetColorMod(RGB(0, 180, 0), 4), a
-- smooth add. On WA's pink worm that is a pale peach, not a green: a green
-- multiply, lit by the green and glowing in it, reads as PX's zombie art.
local TINT = { color = 0x60FF60, light = 0.35, glow = 0.8 }
local ATTACK_COOLDOWN = 60
local LEAP_RANGE = 400
-- The punch is WA's own Fire Punch, used without firing it (worm:use): its
-- uppercut, flames, hit, hole and sound. PX's script fired the real one
-- (weapon 16, then Space) until online games made it fall back to PunchIt, a
-- hop of the same -6 with its own hits, which worm:use makes unneeded. The
-- profile's Fire Punch record sets the damage and knock (WA's: 30).
local PUNCH = "stock.fire_punch"

-- The worm states PX lets punch (WS_IDLE, WS_JUMP, WS_WALKING, WS_SLIDING,
-- WS_JUMPPREPARE).
local CAN_PUNCH = { standing = true, walking = true, sliding = true, jumping = true, jump_prepare = true }

-- is_soldier(worm), soldier_name: from the Specialists rules.
function zombie.install(is_soldier, soldier_name)
  local shared = require("lib/shared")
  local zombies, spent = {}, {}         -- by worm id; spent: may not turn again
  local turning = {}                    -- a lethal hit was cut to 1 HP
  local attack_cd = {}
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
    worm.tint = TINT
    worm.name = NAME
    wa.log("Specialists: worm " .. worm.id .. " comes back as a zombie")
  end

  -- Lightning (PX's LightningHit override): a zombie is a Soldier again, no
  -- HP added, and may turn once more. True: the strike adds no health.
  shared.lightning_restores_worm = function(worm)
    if not zombies[worm.id] or out[worm.id] then return false end
    zombies[worm.id], spent[worm.id] = nil, nil
    worm.selectable = true
    worm.tint = nil
    worm.name = soldier_name
    wa.log("Specialists: Lightning restores worm " .. worm.id)
    return true
  end

  -- A hit or blast that would kill a Soldier who may still turn leaves it
  -- 1 HP and its push; it turns on its next frame. WA's own answer decides
  -- (hit.expected, DLLs after 0.9.8: what WA will take, 0 for a hit it drops
  -- or a worm the scheme's Phased Worms spares). Without it a hit's amount
  -- does, and a blast is left to WA: its amount is its power, which reaches
  -- every worm on the map (a Soldier at 42 HP far from a 50 blast turned).
  -- Whatever still brings a Soldier to 0 HP (fall damage, which sends no
  -- hurt; Double Damage on the cut; a blast on an older DLL) raises it from
  -- 0 HP instead (worm:heal from_zero).
  wa.on.hurt(function(hit)
    local worm = hit.worm
    if hit.phase ~= "pre" or not worm or zombies[worm.id] or spent[worm.id] then return end
    if not is_soldier(worm) or not alive(worm) then return end
    if hit.kind == "percent" or hit.kind == "poison" then return end
    local takes = hit.expected
    if takes == nil then
      if hit.kind == "blast" then return end
      takes = hit.amount
    end
    if takes and takes >= worm.hp then
      if hit.kind == "blast" then hit.damage = worm.hp - 1 else hit.amount = worm.hp - 1 end
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
    for _, id in ipairs(wa.sorted(attack_cd)) do
      attack_cd[id] = attack_cd[id] > 1 and attack_cd[id] - 1 or nil
    end
    local clock = target and wa.world.turn_clock()
    running = clock ~= nil and last_clock ~= nil and clock < last_clock
    last_clock = clock
    team_out_check(wa.worms.all())
  end

  local function face(worm, x) worm.facing = worm.x < x and 1 or -1 end

  -- A Soldier that turns on its own team's turn is no longer the player's:
  -- Tab hands the turn to the team's next worm, which WA's turn order now
  -- picks past the zombie (worm.selectable). Specialists keeps worm
  -- selection open all turn (world +0x5EC); where the scheme has none, Tab
  -- can't, and the turn's clock is run out instead.
  local function hand_over(worm)
    worm:input({ key = "tab" })
    if worm.turn then
      worm:clear_keys()
      if wa.world.turn_clock() > 0 then
        wa.world.set_turn_clock(0)
        wa.log("Specialists: worm " .. worm.id .. " turned on its own turn; no worm selection, the turn ends")
      end
    else
      wa.log("Specialists: worm " .. worm.id .. " turned on its own turn; the team's next worm takes it")
    end
  end

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
        z:use(PUNCH)
      end
      if x < tx + 20 and x > tx - 20 and y > ty - 12 and y < ty + 90 then return end
      if z.state == "standing" or z.state == "walking" then
        if x > tx then z:input({ key = "left" }) elseif x < tx then z:input({ key = "right" }) end
      end
    elseif z.state == "standing" then
      leap(z, t)
    end
  end

  wa.on.worm_message(function(worm)
    local frame = wa.world.frame()
    if frame ~= last_frame then
      last_frame = frame
      each_frame()
    end
    if zombies[worm.id] and worm.name ~= NAME and alive(worm) then
      -- Its grave brought back (the Health Zone, Lightning): a new body WA
      -- builds from the team's lobby record, which WA's turns pick and
      -- nothing tints. A Soldier again, one that has had its turn.
      zombies[worm.id], out[worm.id], attack_cd[worm.id] = nil, nil, nil
      wa.log("Specialists: worm " .. worm.id .. " comes back from its grave a Soldier")
    end
    if worm.state == "drowning" then spent[worm.id] = true end
    if not zombies[worm.id] then
      if is_soldier(worm) and not spent[worm.id] and worm.state ~= "drowning"
        and (turning[worm.id] or worm.hp <= 0) and worm.state ~= "dying" and worm.state ~= "dead" then
        turn(worm)
      end
      return
    end
    if worm.turn then hand_over(worm) end
    if out[worm.id] or not alive(worm) then return end
    act(worm)
  end, { msgs = { wa.msg.FRAME_FINISH } })
end

return zombie
