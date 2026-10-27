-- PX custom_taze: hold a worm in the tazed pose, then release it with a push.
-- hurt_electric(worm, damage, opts), taze(worm, opts),
-- set_message_electric(frames, push_x, push_y, retain), set_message_electric_missile(frames).
-- taze's opts.damage is applied on release, like PX's ReceiveDmg; opts.push_scale
-- multiplies the release push (the tazed mine uses it for 116/100).
-- set_message arms the next hit for 8 frames; the hit's own damage still applies.
-- Arm a blast before it explodes; an on_explode callback runs after the damage.
-- A 0 HP worm awaiting death may still be hit, pushed and tazed: the engine
-- clears WA's ENT_IS_STATIC before those writes land (physics.rs).
-- The caller loads tazed1/2, lightning/glow.png and tazer_loop.wav.

local M = {}

local DEFAULT_FRAMES = 25
local DEFAULT_PUSH_X, DEFAULT_PUSH_Y = 0, -4
local HIT_WINDOW = 8
local BLAST_WINDOW = 10
-- Exported through `wf-lib/electric`; the qualified paths resolve through
-- this bundle's asset namespace, so consumers do not copy the art/sound.
local SHEET1 = "wf-lib/electric/sprites/electric_grenade/tazed1"
local SHEET2 = "wf-lib/electric/sprites/electric_grenade/tazed2"
local GLOW = "wf-lib/electric/sprites/lightning/glow.png"
local LOOP = "wf-lib/electric/sounds/lightning/tazer_loop.wav"
local DEPTH = wa.depth and (wa.depth.WORMS or wa.depth.BEHIND_TERRAIN) or 0x80000

-- The caller's catalogue usually lists these; load them if it did not.
if wa.assets and wa.assets.load then
  pcall(wa.assets.load, {
    sprites = { SHEET1, SHEET2, GLOW },
    sounds = { LOOP },
    gpu_prefix = "wf-lib/electric/sprites/",
  })
end

local active = {}       -- array, for the tick and the draw
local by_worm = {}      -- worm id -> taze
local armed_hit, armed_blast
local spawned = false
local applying = false

local function now()
  return wa.world.frame() or 0
end

-- Kept for callers; the engine owns the static/death guard now.
local function can_affect(worm)
  return worm ~= nil
end
M.can_affect = can_affect

local function options(opts)
  opts = opts or {}
  return {
    frames = opts.frames or DEFAULT_FRAMES,
    push_x = opts.push_x or 0,
    push_y = opts.push_y or DEFAULT_PUSH_Y,
    push_scale = opts.push_scale or 1,
    retain = opts.retain and true or false,
    damage_now = opts.damage_now and true or false,
    sheet = opts.sheet,
    glow = opts.glow == nil and GLOW or opts.glow,
    sound = opts.sound == nil and LOOP or opts.sound,
    draw = opts.draw ~= false,
  }
end

local function remove(t)
  by_worm[t.worm.id] = nil
  for i = #active, 1, -1 do
    if active[i] == t then table.remove(active, i); break end
  end
end

local function begin(worm, opts, damage)
  if not can_affect(worm) then return end
  local id = worm.id
  local t = by_worm[id]
  if t then
    -- A second link extends the hold and adds damage; the first push stays.
    t.frames = math.max(t.frames, opts.frames)
    if damage > 0 then
      if opts.damage_now then
        applying = true
        worm:hurt(damage)
        applying = false
      else
        t.damage = t.damage + damage
      end
    end
    return
  end
  if opts.damage_now and damage > 0 then
    applying = true
    worm:hurt(damage)
    applying = false
    damage = 0
  end
  local vx, vy = worm.vx or 0, worm.vy or 0
  t = {
    worm = worm,
    frames = opts.frames,
    phase = 0,
    damage = damage,
    push_x = opts.retain and vx or opts.push_x,
    push_y = opts.retain and vy or opts.push_y,
    push_scale = opts.push_scale,
    sheet = opts.sheet or (((worm.id + now()) % 2 == 0) and SHEET1 or SHEET2),
    glow = opts.glow,
    sound = opts.sound,
    sound_age = 0,
    draw = opts.draw ~= false,
  }
  active[#active + 1] = t
  by_worm[id] = t
  worm:take{ turn = "freeze" }
  worm.body_visible = false
  worm.vx, worm.vy = 0, 0
  if t.sound and wa.sound and wa.sound.play then wa.sound.play(worm, t.sound) end
end

local function finish(t)
  remove(t)
  local worm = t.worm
  worm.body_visible = true
  if t.damage > 0 and (worm.hp or 0) > 0 then
    applying = true
    worm:hurt(t.damage)
    applying = false
  end
  -- A worm killed during the hold gets no extra damage above, but the hold
  -- still releases it with its push; the engine clears WA's static flag.
  -- Hand the worm back moving at the push, whatever the HP: a worm killed by
  -- the hit still flies, and still dies once WA runs the death. `push_scale`
  -- lets a caller raise the captured blast push (the tazed mine's 116/100).
  local s = t.push_scale or 1
  local px, py = t.push_x * s, t.push_y * s
  if worm.taken then
    worm:release(px, py, { tumble = true })
  else
    worm.vx, worm.vy = px, py
  end
end

local function tick()
  local frame = now()
  for i = #active, 1, -1 do
    local t = active[i]
    local worm = t.worm
    t.frames = t.frames - 1
    t.phase = (t.phase + 0.1) % 1
    -- WA's blast may re-show or release the worm after the hit; keep the
    -- pose on it for the whole hold, even if it has 0 HP and is waiting to die.
    worm.body_visible = false
    if not worm.taken then worm:take{ turn = "freeze" } end
    worm.vx, worm.vy = 0, 0
    t.sound_age = t.sound_age + 1
    if t.sound and t.sound_age % 46 == 0 and wa.sound and wa.sound.play then
      wa.sound.play(worm, t.sound)
    end
    if t.frames <= 0 then finish(t) end
  end
  if armed_hit and frame > armed_hit.expires then armed_hit = nil end
  if armed_blast and frame > armed_blast.expires then armed_blast = nil end
end

wa.on.worm_message(function(worm)
  if spawned then return end
  spawned = true
  wa.actors.spawn({
    sprite = false, x = 0, y = 0, gravity = false, collide = false,
    persist = true, drown = false, owner = worm, on = tick,
  })
end, { msgs = { wa.msg.FRAME_FINISH } })

local function taze_from(hit, arm)
  if not arm or hit.phase ~= "post" or hit.lost <= 0 then return end
  if now() > arm.expires then return end
  if arm.owner and (not hit.attacker or hit.attacker.id ~= arm.owner) then return end
  local worm = hit.worm
  if not worm or not can_affect(worm) then return end
  if worm.taken and not by_worm[worm.id] then return end
  begin(worm, arm, 0)
end

wa.on.hurt(function(hit)
  if applying then return end
  if hit.kind == "hit" or hit.kind == "percent" then
    taze_from(hit, armed_hit)
  elseif hit.kind == "blast" then
    taze_from(hit, armed_blast)
  end
end)

function M.taze(worm, opts)
  if not worm or not can_affect(worm) then return end
  if worm.taken and not by_worm[worm.id] then return end
  opts = opts or {}
  begin(worm, options(opts), math.max(0, opts.damage or 0))
end

function M.hurt_electric(worm, damage, opts)
  if not worm or not can_affect(worm) then return end
  if worm.taken and not by_worm[worm.id] then return end
  begin(worm, options(opts), math.max(0, damage or 0))
end

function M.set_message_electric(frames, push_x, push_y, retain_speed, window)
  armed_hit = options({
    frames = frames or DEFAULT_FRAMES,
    push_x = push_x or 0,
    push_y = push_y or DEFAULT_PUSH_Y,
    retain = retain_speed,
  })
  armed_hit.expires = now() + (window or HIT_WINDOW)
end

-- `owner` narrows it to that worm's blasts; `window` covers a stock missile's
-- flight when the pack cannot arm just before the explosion.
function M.set_message_electric_missile(frames, owner, window)
  armed_blast = options({
    frames = frames or DEFAULT_FRAMES,
    retain = true,
  })
  armed_blast.owner = owner and owner.id
  armed_blast.expires = now() + (window or BLAST_WINDOW)
end

if wa.on.draw and wa.draw.quad then
  local draw_warned = false
  local QUAD = {
    points = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
    blend = "alpha", depth = DEPTH,
  }
  local function square(sprite, frame, blend, color, x, y, half)
    local p = QUAD.points
    p[1][1], p[1][2] = x - half, y - half
    p[2][1], p[2][2] = x + half, y - half
    p[3][1], p[3][2] = x + half, y + half
    p[4][1], p[4][2] = x - half, y + half
    QUAD.sprite, QUAD.frame, QUAD.blend, QUAD.color = sprite, frame, blend, color
    local ok, err = pcall(wa.draw.quad, QUAD)
    if not ok and not draw_warned then
      draw_warned = true
      if wa.log then wa.log("electric_damage draw: " .. tostring(err)) end
    end
  end
  local function colour(a, r, g, b)
    return (math.floor(a) << 24) | (r << 16) | (g << 8) | b
  end
  local rnd = wa.draw.random or function() return 0.5 end
  wa.on.draw(function()
    for i = 1, #active do
      local t = active[i]
      local worm = t.worm
      if t.draw then
        local x, y = worm.x, worm.y
        if x and y then
          square(t.sheet, math.floor(t.phase * 4) % 4,
            "alpha", 0xFFFFFFFF, x, y, 30)
          if t.glow then
            local size = 128 * (0.4 + 0.3 * rnd())
            square(t.glow, 0, "add", colour(255, 80, 100, 255),
              x, y, size / 2)
          end
        end
      end
    end
  end)
end

return M
