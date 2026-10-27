-- Taze a mine from any electric weapon. PX only marks the mine
-- (weapon_electric_mine.c:14-27); its DoExplosion then replaces the blast with
-- a 1.25x electric one (:93-100). This keeps WA's stock blast and, once the
-- mine is gone, gives the worms in PX's electric field the artificial taze
-- (custom_taze.c:64-103): 15 damage on release and the captured blast push
-- scaled to 116/100. Call M.taze(mine, opts) before the mine can be freed; the
-- module owns the mine emitter, trail, per-frame watch and driver. The caller
-- must load the effects SDK's trail.BEAM and trail.GLOW sprites.

local fx = require("wf-lib/effects/px_effects")
local zap = require("lib/electric_damage")
local trail = require("wf-lib/effects/trail")

trail.install()

local M = {}

local STOCK_DAMAGE = 45   -- WA's stock mine damage
local STOCK_PUSH = 100    -- its push power
local TAZE_DAMAGE = 15    -- released after the hold; PX's tazed mine is 55 total
local TAZE_PUSH = 116     -- PX's tazed mine push, i.e. 1.16x the captured 100
local DEFAULT_FRAMES = 20 -- TazeArtificial(20 + 11*tier*1.5), tier 0

local tazed = {}       -- id -> entry
local order = {}       -- array of entries, oldest first
local seen_frame = nil
local driver = nil

local function frame()
  return wa.world.frame() or 0
end

local function any_worm()
  for _, w in ipairs(wa.worms.all()) do
    if w.kind == "worm" then return w end
  end
end

-- WA's static corpse (0 HP) is not tazed; the stock blast still moves it, but
-- the artificial hold on a corpse would keep it from settling.
local function can_taze(w)
  return w ~= nil and (w.hp == nil or w.hp > 0)
end

local function taze_blast(e)
  local list
  local nearby = wa.world and wa.world.electrical_nearby
  if nearby then
    list = nearby(e.x, e.y, e.radius, false)
  else
    list = wa.worms.all()
  end
  local r2 = e.radius * e.radius
  for _, obj in ipairs(list) do
    if obj.kind == "worm" then
      local dx, dy = (obj.x or 0) - e.x, (obj.y or 0) - e.y
      if dx * dx + dy * dy <= r2 and can_taze(obj) then
        -- The stock blast already pushed the worm; retain hands that velocity
        -- back after the hold, scaled to the tazed mine's push. The release
        -- damage rides on the same hold, as PX's ReceiveDmg does.
        zap.taze(obj, {
          frames = e.frames, retain = e.retain,
          damage = e.taze_damage, push_scale = e.push_scale,
        })
      end
    end
  end
end

-- Drop the map/emitter/trail; the caller removes the entry from `order`.
local function drop(e)
  if e.effect then e.effect:remove() end
  if e.trail_key then trail.drop(e.trail_key) end
  if tazed[e.id] == e then tazed[e.id] = nil end
end

local function remove_entry(e)
  drop(e)
  for i = #order, 1, -1 do
    if order[i] == e then table.remove(order, i); break end
  end
end

local function tick()
  local now = frame()
  if seen_frame == now then return end
  seen_frame = now
  if #order == 0 then return end
  local present = {}
  for _, m in ipairs(wa.mines.all()) do present[m.id] = m end
  for i = #order, 1, -1 do
    local e = order[i]
    local m = present[e.id]
    if m and m.uid == e.uid then
      e.x, e.y = m.x, m.y
      -- The mine is stationary, so PX's attached trail would never add a point.
      -- A tiny deterministic orbit gives it something to draw (visual only).
      local a = (now + e.id) * 0.12
      local c, sn = wa.math.cos(a), wa.math.sin(a)
      trail.sample(e.trail_key, e.x + c * 2.5, e.y + sn * 2.5,
        -sn * 0.25, c * 0.25)
    else
      -- A tazed mine lost under water is removed too; do not taze the worms
      -- at the waterline for it. A real explosion above the water still tazes.
      local water = wa.world and wa.world.water and wa.world.water()
      if not water or water <= 0 or e.y < water then taze_blast(e) end
      drop(e)
      table.remove(order, i)
    end
  end
end

local function ensure_driver(owner)
  if driver and driver.id ~= 0 then return driver end
  driver = wa.actors.spawn{
    sprite = false, x = 0, y = 0, gravity = false, collide = false,
    persist = true, drown = false, owner = owner, on = tick,
  }
  return driver
end

-- The driver can die with its owner; keep one while a mine is pending.
wa.on.worm_message(function(worm)
  if #order > 0 then ensure_driver(worm) end
end, { msgs = { wa.msg.FRAME_FINISH } })

-- opts: owner (actor/worm for the emitter, trail and driver), damage (field
-- radius basis, default WA's stock 45), radius, frames, retain, taze_damage
-- (released after the hold, default 15), push/push_from (default 116/100) or
-- push_scale.
function M.taze(mine, opts)
  opts = opts or {}
  if not mine or not mine.id then return nil end
  local id, uid = mine.id, mine.uid
  local existing = tazed[id]
  if existing then
    if existing.uid == uid then return existing end
    -- WA reused the id: retire the old entry before adding the new mine.
    remove_entry(existing)
  end
  local damage = opts.damage or STOCK_DAMAGE
  local push = opts.push or TAZE_PUSH
  local push_from = opts.push_from or STOCK_PUSH
  local e = {
    id = id, uid = uid, x = mine.x, y = mine.y,
    radius = opts.radius or ((math.floor(damage * 1.25) + 2) * 2),
    frames = opts.frames or DEFAULT_FRAMES,
    retain = opts.retain ~= false,
    taze_damage = opts.taze_damage or TAZE_DAMAGE,
    push_scale = opts.push_scale or (push / push_from),
  }
  tazed[id] = e
  order[#order + 1] = e
  local owner = opts.owner or any_worm()
  ensure_driver(owner)
  if fx and fx.emitter then
    e.effect = fx.emitter{
      x = e.x, y = e.y, owner = owner, preset = "electric", trail = false,
      follow = function()
        for _, m in ipairs(wa.mines.all()) do
          if m.id == id and m.uid == uid then return m.x, m.y end
        end
      end,
    }
  end
  -- PX's TazeMine gives its first effect a trail. The effects emitter's own
  -- trail may be off if another bundle installed fx without one, and a
  -- stationary mine has no motion to sample anyway; this trail is explicit.
  local preset = fx.PRESETS and fx.PRESETS.electric and fx.PRESETS.electric.trail
  e.trail_key = "taze_mine:" .. id .. ":" .. uid
  trail.add(e.trail_key, owner, {
    every = preset and preset.every, max = preset and preset.max,
    vanish = preset and preset.vanish,
    core_w = preset and preset.core_w, glow_w = preset and preset.glow_w,
    r = preset and preset.r, g = preset and preset.g, b = preset and preset.b,
    depth = (wa.depth.OBJECTS or 0) + 1,
  })
  return e
end

function M.forget(id)
  local e = id and tazed[id]
  if not e then return false end
  remove_entry(e)
  return true
end

function M.pending()
  return #order
end

return M
