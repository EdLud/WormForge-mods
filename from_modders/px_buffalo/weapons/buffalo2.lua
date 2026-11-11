-- Buffalo of Lies: PX's charging buffalo, three per shot.

local sb = require("wf-lib/px_sprite_builder")

local M = {}

local SHEET = "sprites/buffalo/buffalo.png"
local ICON = "sprites/buffalo/icon.png"
local SND = "sounds/buffalo/"

local prevX = {}
local prevY = {}

local BUFFALOS = 3
local START_FRAMES = 118 -- buffalostart.wav, 2.35 s at 50 fps
local WALK_FRAMES = 84 -- buffaloride.wav, 1.68 s
local RUN_PHASE = 0.032 -- PX: 0.001 * 20 * 1.6
local SINK_PHASE = 0.0145 -- PX: 0.001 * 20 * 0.725
local SINK_TURN = 0.05
local WALK_SPEED = 1.3 -- the record's roam.walk_speed
local RECOIL_FRAMES = 20 -- how long the backwards/up pop lasts
local GROUND_VY = 0.8 -- the roam sits still vertically when grounded
local HALF_PI = math.pi / 2

local info = {}
local shot
local shot_seq = 0
local launching
local installed = false
local mode = "straight"

local function placed(ctx)
  local informed = false
  if type(ctx.weapons) == "table" then
    informed = true
    if ctx.weapons[ctx.id] ~= nil then return true end
  end
  if type(ctx.placed) == "table" then
    informed = true
    for _, weapon in ipairs(ctx.placed) do
      if weapon == ctx.id or (type(weapon) == "table" and weapon.id == ctx.id) then
        return true
      end
    end
  end
  return not informed
end

local function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
  end
end

local function sign(n) return n > 0 and 1 or -1 end

local function gone(id)
  return function(a)
    local t = info[id]
    if t and t.seen then t.seen = false return end
    info[id] = nil
    a:despawn()
  end
end

local function spawn(o)
  local previous = launching
  launching = { side = o.side, owner = o.owner, shot_id = o.shot_id,
    recoil_side = o.recoil_side, exploded = false }
  local ok, id = pcall(wa.weapons.launch, {
      weapon = o.weapon, owner = o.owner, x = o.x, y = o.y,
      vx = o.vx, vy = o.vy,
    })
  local context = launching
  launching = previous
  if not ok then
    wa.log("buffalo launch: " .. tostring(id))
    return nil, false
  end
  if not id or context.exploded then return nil, context.exploded end
  info[id] = { side = o.side, owner = o.owner, shot_id = o.shot_id,
    phase = 0, rot = 0, sinking = false, current = true, seen = false,
    recoil_frames = o.recoil_frames or 0, recoil_speed = o.recoil_speed,
    recoil_side = o.recoil_side }
  return id, false
end

function M.install(ctx)
  if installed or not placed(ctx) then return end
  installed = true
  mode = ctx.option("direction") or "straight"

  local function on_fire(fire)
    local owner = fire.worm or current_worm()
    local vx, vy = fire.vx or 0, fire.vy or 0
    local side = (vx ~= 0 and sign(vx))
    or (owner and owner.facing) or 1
    shot_seq = shot_seq + 1
    shot = { id = shot_seq, owner = owner, side = side, spawned = 1, age = 0,
      roar = wa.random(60, 80) }
    wa.sound.play(owner, SND .. "start.wav")
    local id, exploded = spawn({ weapon = ctx.id, owner = owner,
        x = fire.x, y = fire.y, vx = vx * 0.25, vy = vy * 0.25, side = side,
        shot_id = shot.id })
    if not id and not exploded then shot = nil end
  end

  local function on_explode(ev)
    local t = ev.missile and info[ev.missile]
    local synchronous = false
    if not t and launching and not launching.exploded then
      launching.exploded = true
      synchronous = true
      t = { side = launching.side, owner = launching.owner,
        shot_id = launching.shot_id, current = true,
        recoil_side = launching.recoil_side }
    end
    if not t then return end
    if not synchronous then info[ev.missile] = nil end
    if not shot or t.shot_id ~= shot.id or not t.current then return end
    local water = wa.world.water()
    if t.sinking or (water and ev.y >= water + 15) then
      shot = nil
      return
    end
    if shot.spawned >= BUFFALOS then
      shot = nil
      return
    end
    local recoil_side = -t.side
    if mode == "opposite" then
      shot.side = -shot.side
    elseif mode == "random" then
      shot.side = shot.side * (wa.random(0, 1) == 0 and -1 or 1)
    end
    local s = wa.random(131072, 212992) / 65536
    shot.spawned = shot.spawned + 1
    local id, exploded = spawn({ weapon = ctx.id, owner = shot.owner,
        x = ev.x, y = ev.y, vx = shot.side * s, vy = -s, side = shot.side,
        recoil_frames = RECOIL_FRAMES, recoil_speed = s,
        recoil_side = recoil_side, shot_id = shot.id })
    if not id and not exploded then
      shot.spawned = shot.spawned - 1
      shot = nil
    end
  end

  local function manual_explode(missile)
    local t = missile
    local synchronous = false
    if not t and launching and not launching.exploded then
      launching.exploded = true
      synchronous = true
      t = { side = launching.side, owner = launching.owner,
        shot_id = launching.shot_id, current = true,
        recoil_side = launching.recoil_side }
    end
    if not t then return end
    if not synchronous then info[ev.missile] = nil end
    if not shot or t.shot_id ~= shot.id or not t.current then return end
    local water = wa.world.water()
    if t.sinking or (water and ev.y >= water + 15) then
      shot = nil
      return
    end
    if shot.spawned >= BUFFALOS then
      shot = nil
      return
    end
    local recoil_side = -t.side
    if mode == "opposite" then
      shot.side = -shot.side
    elseif mode == "random" then
      shot.side = shot.side * (wa.random(0, 1) == 0 and -1 or 1)
    end
    local s = wa.random(131072, 212992) / 65536
    shot.spawned = shot.spawned + 1
    local id, exploded = spawn({ weapon = ctx.id, owner = shot.owner,
        x = ev.x, y = ev.y, vx = shot.side * s, vy = -s, side = shot.side,
        recoil_frames = RECOIL_FRAMES, recoil_speed = s,
        recoil_side = recoil_side, shot_id = shot.id })
    if not id and not exploded then
      shot.spawned = shot.spawned - 1
      shot = nil
    end 
    t:remove()
    
  end

  local function isStill(mis)
    if not prevX[mis.id] then prevX[mis.id] = 0 end
    if not prevY[mis.id] then prevY[mis.id] = 0 end
    if prevX[mis.id] == mis.x and prevY[mis.id] == mis.y then
      return true
    end
    if mis.vx == 0 and mis.vy == 0 then
      return true
    end

    return false
  end

  wa.on.missile_frame(function(m)
    local t = info[m.id]
    if not t then return end
    if m.phase == "pre" then
      m.sprite = 0
      if t.recoil_side then
        m.vx = t.recoil_side * t.recoil_speed
        if t.recoil_frames > 0 then t.recoil_frames = t.recoil_frames - 1 end
      end
      return
    end

    if t.recoil_side and t.recoil_frames == 0
      and math.abs(m.vy) < GROUND_VY
      and m.vx * t.side > 0 and math.abs(m.vx) <= WALK_SPEED + 0.2 then
      t.recoil_side = nil
      m.vx = t.side * WALK_SPEED
    end

    local water = wa.world.water()
    if water and m.y > water + 15 then t.sinking = true end
    t.phase = t.phase + (t.sinking and SINK_PHASE or RUN_PHASE)
    if t.phase > 1.0 then t.phase = 0.0 end
    local frame = math.floor(t.phase * 20) % 20

    if t.sinking then
      t.rot = t.rot + SINK_TURN * -t.side
      if math.abs(t.rot) >= HALF_PI then t.rot = HALF_PI * -t.side end
      vx = 0
    end

    prevX[t.id] = t.x prevY[t.id] = t.y

    if t.current and shot and t.shot_id == shot.id then
      shot.age = shot.age + 1
      if shot.age == START_FRAMES then
        wa.sound.play(shot.owner, SND .. "ride.wav")
      elseif shot.age > START_FRAMES
        and (shot.age - START_FRAMES) % WALK_FRAMES == 0 then
        wa.sound.play(shot.owner, SND .. "ride.wav")
      end
      if shot.age % shot.roar == 0 and not t.sinking then
        shot.roar_alt = not shot.roar_alt
        wa.sound.play(shot.owner,
          SND .. (shot.roar_alt and "roar1.wav" or "roar2.wav"))
      end
    end

    if not t.actor then
      t.actor = wa.actors.spawn({ sprite = SHEET, x = m.x, y = m.y - 10,
          gravity = false, collide = false,
          owner = t.owner or current_worm(), on = gone(m.id) })
    end
        
    if isStill(t) then 
      t.actor:explode({ damage = 50, id = 100, at = "below" })
      t.manual_esplode(t)
    return end

    local a = t.actor
    a.x, a.y, a.vx, a.vy = m.x, m.y - 10, 0, 0
    a.facing = t.side
    a:frame(frame)
    a:gfx({ angle = math.deg(t.rot), depth = wa.depth.OBJECTS })
    t.seen = true
  end)

  wa.weapons.replace({
      wep = "weps/buffalo_w.wep",
      name = "Buffalo of Lies",
      panel_icon = ICON,
      worm_sprites = sb.PX_POSTURE,
      hold = {
        thrown = true, sheet = SHEET, frames = 1,
        hand = sb.PX_HANDS[1],
        hand_radius = -10.0,
        hand_rotation = 0.0,
        hand_radial_rotation = -0.13,
        hand_scale = 1.0,
        weap_radius = -18.0,
        weap_rotation = 0.5,
        weap_radial_rotation = 0.22,
        static = { weap = -0.075, hand = 0.45 },
        keep_while_firing = false,
      },
      sounds = { SND .. "start.wav", SND .. "ride.wav",
        SND .. "roar1.wav", SND .. "roar2.wav" },
      params = { gpu_prefix = "sprites/", sprite_columns = 1 },
      handling = { retreat = 3000, ends_turn = true },
      missile = { explosion = { power = 50 } },
      on_fire = on_fire,
      on_explode = on_explode,
    })
end

return M
