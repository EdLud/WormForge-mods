-- wfws_sprite_builder.lua -- WFWS's own fork of PX's sprite builder.
--
-- Two layers of gating:
--
--   IDENTITY (decided once, on first sight): which kind of missile is this?
--     primary, cluster bit, or an extra `roles` entry. Cached per missile id.
--
--   STATE (re-evaluated every pre phase): what is it doing right now?
--     homing, roaming, emitting gas... Each state may swap the art, the
--     animation, or hand the missile back to WA (native = true).
--
--   DIG is not a state: a digging round has no art of its own. The record's
--     dig sprite indexes are zeroed (a mole or the wsv* frames would draw
--     underneath), and the builder simply cycles the flight sheet while the
--     nose is in the land. See `dig =` below.
--
-- API:
--
--   sb.flight(ctx, {
--     weapon = ctx.id,
--     sheet = "...", anim = "track", ...        -- primary art
--     bits  = { sheet = "...", ... } | "inherit" | nil/false (native)
--     is_bit = function(m) ... end,             -- optional classifier override
--     roles  = { { name = "x", match = function(m) ... end, sheet = "..." } },
--     dig    = true | { probe = 6, spread = 3, hold = 3, need = 2 },
--     states = {
--       { scope = "main" | "bit" | "any" | <role name>,
--         sig  = 245 | { 246, 247, 248 },       -- native sprite ids that mean
--                                               -- "in this state"
--         when = function(m) ... end,           -- or any custom test
--         sheet = "...", anim = "...", ...      -- art for this state
--         native = true },                      -- OR: leave WA's art alone
--     },
--   })
--
-- STATE SIGNAL (legacy, `sig`): an old assumption that WA writes the
-- behaviour's own sprite id into m.sprite. It does not -- `m.sprite` is the
-- flight sprite and nothing else -- so new work should time the state (homing
-- arm/time in ms) or probe for it (dig) instead of matching ids. `sig` stays
-- only for bundles that still pass one.
--
-- Default bit test: "zero means cluster bit". WA seeds a missile's flight
-- sprite (`m.sprite`) from its fire params, and a cluster bit's params are the
-- *parent's* copy -- so the primary is the one carrying the record's `sprite`
-- (zeroed while the builder owns the art) and the bits are the zero ones, the
-- opposite of what the field's name suggests. `is_bit` overrides it; when the
-- engine exposes the pellet flag (`m.bit`, MissileEntity+0x150) that is exact.
--
-- Pure data at load: `wa` is touched only inside M.flight and its callbacks.
--
-- Bundle: wfws.sdk (spec/lua_sdk/wfws_sdk). `holds` is exported by the
-- `wf.sdk` dependency, so this bundle requires it by its public module name.

local shared = require("wf-lib/holds")

local M = {}

local ANIM_TYPE = {
  track = 2,
  rotation = 3,
  slow = 1,
  medium = 1,
  fast = 1,
  none = 5,
}
local ANIM_SPEED = { slow = 0.5, medium = 0.8, fast = 1.35 }

local function current_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
  end
end

local function sign(n) return n > 0 and 1 or (n < 0 and -1 or 0) end

function M.cyclical_frame(phase, anim_speed, num_frames)
  if not phase then phase = 0.0 end
  local spd = (anim_speed or 1.0) * 30 / 1000
  phase = phase + spd
  if phase > 0.99 then phase = 0.0 end
  local frame = math.floor(phase * num_frames) % num_frames
  return frame, phase
end

function M.track_angle(vx, vy)
  return -wa.math.atan(vx, vy) - math.pi
end

function M.rotation_turn(prev_rot, vx, vy, spin)
  return (prev_rot or 0) + (spin or 1.0) * 0.5 * (vx * 0.15 + math.abs(vy) * 0.01 * sign(vx))
end

function M.spin_turn(prev_rot, vx, anim_speed)
  return (prev_rot or 0) + (anim_speed or 0.5) * 0.5 * sign(vx)
end

-- ---------------------------------------------------------------------------
-- Digging. A digging record names no art of its own once the builder owns the
-- flight sheet (the generator zeroes `dig.dive_sprite` and `dig.sprite_1..3`),
-- so "digging" is only an animation: the sheet keeps tracking the heading and
-- cycles its frames while the round is inside the land. PX's Bunker Buster
-- tells the two apart by probing the terrain around the nose; four probes, two
-- hits, and it is in the dirt. Coordinates are pixels, like `m.x` / `m.y`.
-- ---------------------------------------------------------------------------
local DIG_PROBE = 6.0   -- pixels ahead of the centre
local DIG_SPREAD = 3.0  -- pixels either side of the heading
local DIG_HOLD = 3      -- frames a clear nose keeps the dig animation on
local DIG_NEED = 2      -- probes that must be solid
local DIG_OFFSETS = { -1.0, -0.34, 0.34, 1.0 }

local function dig_settings(o)
  if o == nil or o == false then return nil end
  local t = type(o) == "table" and o or {}
  return {
    probe = t.probe or DIG_PROBE,
    spread = t.spread or DIG_SPREAD,
    hold = t.hold or DIG_HOLD,
    need = t.need or DIG_NEED,
  }
end

-- Heading of the round, normalized; the last one when it is at rest.
local function heading_of(m, last)
  local vx, vy = m.vx or 0, m.vy or 0
  local len = math.sqrt(vx * vx + vy * vy)
  if len < 0.0001 then return last or { 0.0, 1.0 } end
  return { vx / len, vy / len }
end

-- Four probes across the nose. `wa.land.solid` is WA's own terrain test.
local function in_land(m, dir, d)
  local x, y = m.x, m.y
  if not x or not y then return false end
  local px, py = -dir[2], dir[1]
  local hits = 0
  for i = 1, #DIG_OFFSETS do
    local k = DIG_OFFSETS[i] * d.spread
    if wa.land.solid(x + dir[1] * d.probe + px * k,
                     y + dir[2] * d.probe + py * k) then
      hits = hits + 1
      if hits >= d.need then return true end
    end
  end
  return false
end

-- One frame of dig state for a missile: true while digging.
local function update_dig(m, d, dirs, holds)
  local id = m.id
  local dir = heading_of(m, dirs[id])
  dirs[id] = dir
  if in_land(m, dir, d) then
    holds[id] = d.hold
    return true
  end
  local left = holds[id] or 0
  if left > 0 then
    holds[id] = left - 1
    return true
  end
  return false
end

-- Sentinel: a missile (or state) the builder leaves to WA.
local NATIVE = {}

local function resolve(o)
  local anim = o.anim or "none"
  local cfg = {
    sheet = o.sheet,
    anim = anim,
    anim_type = ANIM_TYPE[anim],
    spin = o.spin or 1.0,
    cyclical = o.cyclical or 0,
    anim_speed = o.anim_speed or 1.0,
    z = o.z or 5.0,
    scale = o.scale or 1.0,
    mirror = o.mirror ~= false,
    frame_fn = o.frame_fn,
    turn_fn = o.turn_fn,
  }
  -- `homing = { arm = ms, time = ms, sheet = "...", ... }`: art for the
  -- homing window, resolved once at install like every other role.
  if type(o.homing) == "table" then
    local h = resolve(o.homing)
    h.arm = o.homing.arm or 0
    h.time = o.homing.time or 0
    cfg.homing = h
  end
  return cfg
end

-- Homing is timed, not detected: WA arms the missile `arm` ms after it is
-- fired and steers it for `time` ms (0 = until it lands or blasts). The game
-- is a 50 Hz lockstep, so a frame is exactly 20 ms on every machine.
local MS_PER_FRAME = 20

local function homing_art(cfg, ms)
  local h = cfg and cfg.homing
  if not h then return cfg end
  local arm = h.arm or 0
  if ms < arm then return cfg end
  if (h.time or 0) > 0 and ms >= arm + h.time then return cfg end
  return h
end

local function sigset(v)
  if v == nil then return nil end
  local s = {}
  if type(v) == "table" then
    for i = 1, #v do s[v[i]] = true end
  else
    s[v] = true
  end
  return s
end

function M.flight(ctx, opts)
  if not opts or not opts.weapon or not opts.sheet then
    wa.log("wfws_sprite_builder.flight: weapon and sheet are required")
    return
  end

  local main = resolve(opts)

  local bit_cfg = NATIVE
  local bit_art = false
  if type(opts.bits) == "table" then
    bit_cfg = resolve(opts.bits)
    bit_art = true
  elseif opts.bits == "inherit" then
    bit_cfg = main
  end

  local extra = {}
  if type(opts.roles) == "table" then
    for i, r in ipairs(opts.roles) do
      extra[i] = { name = r.name or ("role" .. i), match = r.match, cfg = resolve(r) }
    end
  end

  local states = {}
  if type(opts.states) == "table" then
    for i, s in ipairs(opts.states) do
      states[i] = {
        scope = s.scope or "any",
        sigs = sigset(s.sig),
        when = s.when,
        cfg = s.native and NATIVE or resolve(s),
      }
    end
  end

  local owner = opts.owner

  local kind = {}        -- [id] = { ident = "main"|"bit"|role name, base = cfg }
  local sig = {}         -- [id] = last nonzero m.sprite seen (the state signal)
  local active = {}      -- [id] = cfg in force this frame
  local follow = {}      -- [id] = { actor, cfg, gen, seen }
  local spin_ang = {}
  local cycl_phase = {}
  local dig_dir = {}     -- [id] = last heading, for the terrain probes
  local dig_hold = {}    -- [id] = frames left of "digging"
  local dig = dig_settings(opts.dig)
  local age = {}         -- [id] = frames since first sight, for homing ms
  local logged = {}      -- [id] = frames logged so far (opts.log)
  local gen = 0

  -- Identity: first sight, before this module has zeroed m.sprite.
  local function classify(m)
    for i = 1, #extra do
      if extra[i].match(m) then return { ident = extra[i].name, base = extra[i].cfg } end
    end
    local is_bit
    if opts.is_bit then
      is_bit = opts.is_bit(m) and true or false
    elseif m.bit ~= nil then
      -- The engine's own answer (MissileEntity+0x150, `shoot_desc.pellet`).
      is_bit = m.bit and true or false
    else
      -- Flipped default: with a bit sheet configured, the cluster bit is the
      -- missile whose flight sprite is zero (WA hands the primary the
      -- record's `sprite`; a bit inherits the parent's copy of it). Without a
      -- bit sheet there are no bits to tell apart, so everything is the
      -- primary -- otherwise a plain weapon would classify as a bit and draw
      -- nothing, because the bit role is NATIVE.
      is_bit = bit_art and (m.sprite == 0)
    end
    if is_bit then return { ident = "bit", base = bit_cfg } end
    return { ident = "main", base = main }
  end

  -- State: first matching state in scope, else the identity art.
  local function pick(m, ent)
    local s = sig[m.id]
    for i = 1, #states do
      local st = states[i]
      if st.scope == "any" or st.scope == ent.ident then
        if (st.sigs and s and st.sigs[s]) or (st.when and st.when(m)) then
          return st.cfg
        end
      end
    end
    return ent.base
  end

  local function gone(id, g)
    return function(b)
      local f = follow[id]
      if not f or f.gen ~= g then return end   -- stale actor from a state swap
      if f.seen then f.seen = false return end
      follow[id] = nil
      spin_ang[id] = nil
      cycl_phase[id] = nil
      kind[id] = nil
      sig[id] = nil
      active[id] = nil
      dig_dir[id] = nil
      dig_hold[id] = nil
      logged[id] = nil
      age[id] = nil
      b:despawn()
    end
  end

  local function drop_follower(id)
    local f = follow[id]
    if f then
      follow[id] = nil
      f.actor:despawn()
    end
    cycl_phase[id] = nil
  end

  wa.on.missile_frame(function(m)
    if m.weapon ~= opts.weapon then return end
    local id = m.id

    local ent = kind[id]
    if ent == nil then
      ent = classify(m)
      kind[id] = ent
      age[id] = 0
      -- `log = true` for one line per missile's first three frames: what the
      -- identity test actually saw. Turn it off once a convention is settled.
      if opts.log then
        logged[id] = (logged[id] or 0) + 1
        wa.log(string.format("wfws: id=%s sprite=%s ident=%s",
          tostring(m.id), tostring(m.sprite), tostring(ent.ident)))
      end
    elseif opts.log and (logged[id] or 0) < 3 then
      logged[id] = (logged[id] or 0) + 1
      wa.log(string.format("wfws: id=%s sprite=%s ident=%s phase=%s",
        tostring(m.id), tostring(m.sprite), tostring(ent.ident), tostring(m.phase)))
    end

    if m.phase == "pre" then
      if m.sprite ~= 0 then sig[id] = m.sprite end   -- read BEFORE zeroing
      local cfg = pick(m, ent)
      active[id] = cfg
      if cfg == NATIVE then
        -- Hand the sprite back. If our earlier zero stuck, restore the last
        -- signal (VERIFY: m.sprite is writable and WA draws it again).
        if m.sprite == 0 and sig[id] then m.sprite = sig[id] end
      else
        m.sprite = 0
      end
      return
    end

    local base = active[id]
    if base == nil then
      base = pick(m, ent)
      active[id] = base
    end
    if base == NATIVE then
      drop_follower(id)
      return
    end
    age[id] = (age[id] or 0) + 1
    local cfg = homing_art(base, age[id] * MS_PER_FRAME)

    local f = follow[id]
    if f and f.cfg ~= cfg then            -- state changed: new art, new actor
      drop_follower(id)
      f = nil
    end
    if not f then
      gen = gen + 1
      f = {
        cfg = cfg, gen = gen,
        actor = wa.actors.spawn({
          sprite = cfg.sheet, x = m.x, y = m.y,
          gravity = false, collide = false,
          owner = owner or current_worm(), on = gone(id, gen),
        }),
      }
      follow[id] = f
    end
    f.seen = true
    local b = f.actor
    b.x, b.y, b.vx, b.vy = m.x, m.y, 0, 0

    -- Digging: no art of its own, just the sheet cycling while the nose is in
    -- the land. It keeps tracking the heading, so the drill points into the
    -- hole the round is making.
    local digging = dig and update_dig(m, dig, dig_dir, dig_hold) or false

    local rot = 0
    local frame = 0
    if digging then
      rot = M.track_angle(m.vx, m.vy)
      frame, cycl_phase[id] =
        M.cyclical_frame(cycl_phase[id], cfg.anim_speed, math.max(1, cfg.cyclical))
    else
      if cfg.turn_fn then
        rot = cfg.turn_fn(m, spin_ang[id])
        spin_ang[id] = rot
      elseif cfg.anim_type == 2 then
        rot = M.track_angle(m.vx, m.vy)
      elseif cfg.anim_type == 3 then
        rot = M.rotation_turn(spin_ang[id], m.vx, m.vy, cfg.spin)
        spin_ang[id] = rot
      elseif cfg.anim_type == 1 then
        rot = M.spin_turn(spin_ang[id], m.vx, ANIM_SPEED[cfg.anim] or 0.5)
        spin_ang[id] = rot
      end

      if cfg.frame_fn then
        frame = cfg.frame_fn(m)
      elseif cfg.cyclical > 0 then
        frame, cycl_phase[id] = M.cyclical_frame(cycl_phase[id], cfg.anim_speed, cfg.cyclical)
      else
        cycl_phase[id] = nil
      end
    end

    b.facing = cfg.mirror and (m.vx < 0 and -1 or 1) or 1
    b:frame(frame)
    b:gfx({ angle = math.deg(rot) % 360, depth = cfg.z, scale = cfg.scale })
  end)
end

M.PX_POSTURE = shared.PX_POSTURE
M.PX_HANDS = shared.PX_HANDS

return M
