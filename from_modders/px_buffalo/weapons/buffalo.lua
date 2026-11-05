-- Buffalo of Lies: PX's charging buffalo, three per shot.
--
-- PX's CBuffaloManager spawns a CBuffalo (a CMissile on the pack's own roam
-- record); each collision explodes it and the manager spawns the next at the
-- explosion point. The .wep already walks it (action roam, walk speed 1.3),
-- so Lua only runs the three, draws the 20-frame sheet and the sounds.
local sb = require("wf-lib/px_sprite_builder")

-- PX's weapon-less posture. The record keeps the cow as its flight sprite, so
-- WA's placed-weapon held lookup would draw the cow in hand; the weapon's
-- `sprite` is switched to the stock missile below, which has no held sheet.
local POSTURE = {
  weaponlnk = sb.PX_POSTURE.wthrow, weaponlnku = sb.PX_POSTURE.wthrowu,
  weaponlnkd = sb.PX_POSTURE.wthrowd,
  wthrow = sb.PX_POSTURE.wthrow, wthrowu = sb.PX_POSTURE.wthrowu,
  wthrowd = sb.PX_POSTURE.wthrowd,
}

local M = {}

local SHEET = "sprites/buffalo/buffalo.png"
local ICON = "sprites/buffalo/icon.png"
local SND = "sounds/buffalo/"

local BUFFALOS = 3
local START_FRAMES = 118    -- buffalostart.wav, 2.35 s at 50 fps
local WALK_FRAMES = 84      -- buffaloride.wav, 1.68 s
local RUN_PHASE = 0.032     -- PX: 0.001 * 20 * 1.6
local SINK_PHASE = 0.0145   -- PX: 0.001 * 20 * 0.725
local SINK_TURN = 0.05
local WALK_SPEED = 1.3     -- the record's roam.walk_speed
local RECOIL_FRAMES = 20   -- how long the backwards/up pop lasts
local GROUND_VY = 0.8      -- the roam sits still vertically when grounded
local STUCK_WINDOW = 10    -- frames compared to decide a buffalo has not moved
local STUCK_DIST2 = 1      -- squared pixels: less than this is "not moved"
local UNSTICK_TRIES = 3    -- nudges before it explodes anyway
local FACE_LOCK = 100      -- frames (2 s) a new buffalo keeps its sprite side
local FACE_FRAMES = 6      -- frames a new walking direction must hold
local HALF_PI = math.pi / 2

local info = {}
local shots = {}   -- one entry per throw, so several can be alive at once
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

-- Standing on something: moving level, or land a few pixels below.
local function isGrounded(m)
  if math.abs(m.vy) < GROUND_VY then return true end
  return wa.land.solid(m.x, m.y + 10)
end

-- Land in the buffalo's way, at body and knee height.
local function wall_ahead(m, side)
  local x = m.x + side * 14
  return wa.land.solid(x, m.y) or wa.land.solid(x, m.y - 8)
end

local function gone(id)
  return function(a)
    local t = info[id]
    if t and t.seen then t.seen = false return end
    info[id] = nil
    a:despawn()
  end
end

-- A missile spawned at the previous one's impact can explode inside launch(),
-- before it has an id. The launch context lets that synchronous explosion
-- continue the chain instead of being dropped as an unknown missile.
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
    recoil_side = o.recoil_side, face = o.side,
    face_lock = o.face_lock or 0 }
  return id, false
end

function M.install(ctx)
  if installed or not placed(ctx) then return end
  installed = true
  mode = ctx.option("direction") or "straight"

  -- Sends the next buffalo from (x, y). Shared by the native explosion and by
  -- a buffalo that got stuck and is blown up by the script.
  local function chain(t, x, y)
    local shot = shots[t.shot_id]
    if not shot or not t.current then return end
    local water = wa.world.water()
    -- A buffalo that reached the water does not send another one.
    if t.sinking or (water and y >= water + 15) then
      shots[shot.id] = nil
      return
    end
    if shot.spawned >= BUFFALOS then
      shots[shot.id] = nil
      return
    end
    -- PX's recoil is away from the buffalo that just exploded (-LastSide),
    -- not away from the newly chosen direction.
    local recoil_side = -t.side
    if mode == "opposite" then
      shot.side = -shot.side
    elseif mode == "random" then
      -- PX's SignEx(RandomInt(-1, 1)): zero is the negative side.
      shot.side = shot.side * (wa.random(0, 1) == 0 and -1 or 1)
    end
    -- Launch with the chosen side so the ctor's roam Side is that way, then
    -- the pre hook flips the horizontal speed back for PX's recoil pop.
    local s = wa.random(131072, 212992) / 65536
    -- Count it first: a synchronous explosion inside launch() must see this
    -- buffalo as the one that just spawned.
    shot.spawned = shot.spawned + 1
    local id, exploded = spawn({ weapon = ctx.id, owner = shot.owner,
        x = x, y = y, vx = shot.side * s, vy = -s, side = shot.side,
        recoil_frames = RECOIL_FRAMES, recoil_speed = s,
        recoil_side = recoil_side, shot_id = shot.id,
        face_lock = FACE_LOCK })
    if not id and not exploded then
      shot.spawned = shot.spawned - 1
      shots[shot.id] = nil
    end
  end

  local function on_fire(fire)
    local owner = fire.worm or current_worm()
    local vx, vy = fire.vx or 0, fire.vy or 0
    local side = (vx ~= 0 and sign(vx))
    or (owner and owner.facing) or 1
    shot_seq = shot_seq + 1
    local shot = { id = shot_seq, owner = owner, side = side, spawned = 1,
      age = 0, roar = wa.random(60, 80) }
    shots[shot.id] = shot
    wa.sound.play(owner, SND .. "start.wav")
    -- PX's first buffalo takes a quarter of the throw's speed.
    local id, exploded = spawn({ weapon = ctx.id, owner = owner,
        x = fire.x, y = fire.y, vx = vx * 0.25, vy = vy * 0.25, side = side,
        shot_id = shot.id })
    if not id and not exploded then shots[shot.id] = nil end
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
    chain(t, ev.x, ev.y)
  end

  wa.on.missile_frame(function(m)
    local t = info[m.id]
    if not t then return end
    if m.phase == "pre" then
      m.sprite = 0
      -- The ctor took the chosen side; feed the native update the backwards
      -- recoil speed for the pop. Once the timer is up, keep it until the
      -- post hook sees the native roam walking (grounded vy and walk vx);
      -- the timer alone let it walk forward in mid-air.
      if t.recoil_side then
        m.vx = t.recoil_side * t.recoil_speed
        if t.recoil_frames > 0 then t.recoil_frames = t.recoil_frames - 1 end
      end
      return
    end

    -- Release the recoil once its timer is up and the buffalo is grounded.
    -- Not tied to vx: a wall behind zeroes it and the recoil would never end.
    if t.recoil_side and t.recoil_frames == 0 and isGrounded(m) then
      t.recoil_side = nil
      m.vx = t.side * WALK_SPEED
    end

    -- Sprite/walk direction. t.side stays the launch side (it decides the
    -- chain's recoil); t.face tracks where the buffalo really walks, and only
    -- flips after the new direction holds for FACE_FRAMES frames, so a bounce
    -- off a wall or a stall cannot flip it for good. Not during the recoil
    -- pop (backwards on purpose) or while sinking (vx forced to 0).
    t.face = t.face or t.side
    if t.face_lock and t.face_lock > 0 then
      -- Flip protection after an explosion: the sprite keeps the side the
      -- chain chose, whatever the velocity does for the first moments.
      t.face_lock = t.face_lock - 1
      t.face_n = 0
    elseif not t.recoil_side and not t.sinking and math.abs(m.vx) > 0.3 then
      local dir = m.vx > 0 and 1 or -1
      if dir == t.face then
        t.face_n = 0
      else
        t.face_n = (t.face_n or 0) + 1
        if t.face_n >= FACE_FRAMES then t.face, t.face_n = dir, 0 end
      end
    end

    local water = wa.world.water()
    if water and m.y > water + 15 then t.sinking = true end
    t.phase = t.phase + (t.sinking and SINK_PHASE or RUN_PHASE)
    if t.phase > 1.0 then t.phase = 0.0 end
    local frame = math.floor(t.phase * 20) % 20

    if t.sinking then
      t.rot = t.rot + SINK_TURN * -t.face
      if math.abs(t.rot) >= HALF_PI then t.rot = HALF_PI * -t.face end
      m.vx = 0
    end

    local shot = shots[t.shot_id]
    if t.current and shot then
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

    local a = t.actor
    if a then
      a.x, a.y, a.vx, a.vy = m.x, m.y - 10, 0, 0
      a.facing = t.face
      a:frame(frame)
      a:gfx({ angle = math.deg(t.rot), depth = wa.depth.OBJECTS })
      t.seen = true
    end

    -- Stuck check: compare against a snapshot taken STUCK_WINDOW frames ago.
    if t.sinking or t.recoil_frames > 0 or not isGrounded(m) then
      t.snap_age = 0
      return
    end
    if not t.snap_x then t.snap_x, t.snap_y, t.snap_age = m.x, m.y, 0 end
    t.snap_age = t.snap_age + 1
    if t.snap_age < STUCK_WINDOW then return end
    local dx, dy = m.x - t.snap_x, m.y - t.snap_y
    t.snap_x, t.snap_y, t.snap_age = m.x, m.y, 0
    if dx * dx + dy * dy >= STUCK_DIST2 then return end

    t.unstick = t.unstick or 0
    if not wall_ahead(m, t.face) and t.unstick < UNSTICK_TRIES then
      -- Nothing in front: free it instead of blowing it up.
      t.unstick = t.unstick + 1
      t.recoil_side = nil
      m.vx = t.face * WALK_SPEED
      m.vy = -1.5
      return
    end
    if a then a:explode({ damage = 50, id = 100, at = "below" }) end
    info[m.id] = nil
    chain(t, m.x, m.y)
    local ok, err = pcall(function() m:remove() end)
    if not ok then wa.log("buffalo remove: " .. tostring(err)) end
  end)

  wa.weapons.replace({
      wep = "weps/buffalo_w.wep",
      name = "Buffalo of Lies",
      -- The record's cow flight sprite makes WA draw the cow in hand for a
      -- placed weapon. The stock missile has no held sheet, so only `hold`
      -- (the bull) draws; the native missile body stays hidden.
      sprite = "missile",
      sprites = { SHEET },
      panel_icon = ICON,
      worm_sprites = POSTURE,
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
      -- PX overrides the worm's explosion damage with BuffaloDamage = 50.
      missile = { explosion = { power = 50 } },
      on_fire = on_fire,
      on_explode = on_explode,
    })

  -- WA keeps a facing copy (+0x3DC) that lags a turn made while aiming; the
  -- engine's hold reads it, so the bull only flipped when the weapon was
  -- re-equipped. `worm.facing` reads the live turn side (+0x1A8), so copy it
  -- back every frame for the turn's worm.
  wa.on.worm_message(function(w)
    if w.turn then w.facing = w.facing end
  end, { msgs = { wa.msg.FRAME_FINISH } })
end

return M
