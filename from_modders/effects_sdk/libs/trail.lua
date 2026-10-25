-- Project X's effect-manager trail (wklua_and_px/utils/px_effects.c), as a
-- shared effects module: one trail per round, sampled in game frames and drawn
-- with the engine's textured beams (`wa.draw.ribbon`). It is what PX's bullet
-- sets with `linkedEffect1->SetTrail(12, 2, 0)`; TRAIL.md is how to bolt it
-- onto a weapon, and REPORT.md 11.9 is the line-by-line mapping back to
-- px_effects.c.
--
-- Consume it with `require("wf-lib/effects/trail")` after declaring
-- `dependencies = ["effects.sdk"]`. The two beam sheets are this bundle's
-- assets; put `trail.BEAM` and `trail.GLOW` in the component's `sprites` list.
--
--   * At most `max` points (PX's `trailMaxL`, :264), one appended every `every`
--     game frames while the round moves (PX's `treshold`, :266; sampled at
--     :579-582, made at :1210-1233), the oldest dropped past the cap
--     (`DetractTrail`, :1229-1232 and :1235-1248). No point while the round is
--     at rest (:1215), nor one within 0.01 of the point before it (:1223).
--   * `DrawTrail` (:1298-1380) draws two textured beams: a sharp core
--     (`tazer_lightningBeamSprite`) and, wider, a soft glow (`beam_glowSprite`;
--     it runs because `shouldBeamGlow` defaults true, :92). Point i of n has
--     t = (i+1)/(n+1) floored at 0.1 -- type 0, the third `SetTrail` argument,
--     is neither the wavy nor the mid-thick-edge-thin profile (:1311-1323) --
--     and that t is the point's texcoord, its colour scale, and, through the
--     width, how thick it draws.
--   * PX's widths are half widths (`TexturedBeamPoint` lays the section out at
--     +-dx; `textured_beam(draw_quad).PXC:35-47`), and `wa.draw.ribbon` wants
--     the full one, so `core_w` and `glow_w` are already doubled (PX's
--     rayThickness 4.0 and rayGlowThick 6.5, :149-150).
--   * The effect outlives its round: with the link gone `IsTargetMoving()` is
--     true again (:560), so the shed that is left is the vanish -- one point
--     every `vanish` game frames, from the oldest end (:583-587, and
--     trailVanishSpd is 2, :169).
--
-- `trail.sample` is that fill for a round that is not a WA missile: a Lua
-- actor calls it from its own frame callback, passing its id and the frame's
-- position and velocity (the Megashark's bullets do). The missile callback in
-- `trail.install` is a one-line call to the same function, so a round's trail
-- is sampled the same way whichever the engine is flying.

local trail = {}

-- The defaults are PX's bullet's. `add` copies them, so change these once, or
-- pass the same names in `opts` for one trail. `beam` and `glow` are qualified
-- `wf-lib/effects/...` paths: the consuming component must list both in its
-- `sprites` table.
trail.MAX, trail.EVERY, trail.VANISH = 12, 2, 2
trail.CORE_W, trail.GLOW_W = 8.0, 13.0
-- The effect's colour is its CEffectManager constructor's r, g, b, which PX's
-- bullet script does not show: white is a neutral stand-in.
trail.R, trail.G, trail.B = 255, 255, 255
-- nil means `wa.depth.OBJECTS`, which only exists inside install(ctx): the engine
-- refuses `wa` while it is loading a component's file and everything it requires
-- ("a component's file only returns its data; use wa in install(ctx)").
trail.DEPTH = nil
trail.BEAM = "wf-lib/effects/sprites/px_effects/beam.png"
trail.GLOW = "wf-lib/effects/sprites/px_effects/beam_glow.png"

-- Every trail drawn: the live rounds, and the ones outliving them.
local trails = {}
-- Missile id -> its trail, while the round is in the air.
local live = {}
-- One hidden actor, while there is a trail to sample or to shed. It ticks the
-- game frames, so nothing here depends on the render rate.
local driver, tick = nil, 0
-- Game frames a live trail may go unsampled before its round counts as gone.
-- A WA missile fires its callback every game frame while it exists, but a Lua
-- actor may skip one legitimately: the Megashark's bullet arms at 90 px and
-- returns before it moves on that frame. The driver ticks on that same frame,
-- so with 2 the gap reaches `STALE` and the trail ends at the arming frame.
-- Three leaves one skipped frame alive; the vanish starts a frame later than
-- PX's at worst, which the 2-frame shed already hides.
local STALE = 3

local function start_driver(t, owner)
  if driver then return end
  -- The sprite is never seen; it just has to be one the consumer declares in
  -- its `sprites` list. `persist` keeps the clock alive through a nearby blast:
  -- if the driver died
  -- with a round's own explosion, `tick` would freeze and every later trail on
  -- the map would stop shedding (the handle cannot be tested for death from
  -- Lua). The round's end is the driver's only exit, when `trails` empties.
  driver = wa.actors.spawn({
    sprite = t.beam, visible = false, gravity = false, collide = false,
    persist = true, owner = owner,
    on = function(a)
      tick = tick + 1
      for i = #trails, 1, -1 do
        local v = trails[i]
        if v.live and tick - v.seen >= STALE then
          -- Its round stopped firing frames: hit, exploded or gone from the map.
          v.live = false
          live[v.id] = nil
        end
        if not v.live and tick % v.vanish == 0 then
          table.remove(v.pts, 1)
          if #v.pts == 0 then
            -- `table.remove`, not `trails[i] = nil`: a hole anywhere before the
            -- end makes `#trails` unspecified and stops the draw's `ipairs` at
            -- the hole, which reads as "no trail is drawn any more" for every
            -- round, live ones included. The loop runs backwards so shifting the
            -- tail down cannot skip an element.
            table.remove(trails, i)
            live[v.id] = nil
          end
        end
      end
      if #trails == 0 then driver = nil; a:despawn() end
    end,
  })
end

-- Trail the round `id`, owned by `owner` (a worm or a team, as `wa.actors.spawn`
-- wants). `opts` overrides any of the fields above for this trail alone.
function trail.add(id, owner, opts)
  local t = {
    id = id, pts = {}, live = true, seen = tick,
    max = trail.MAX, every = trail.EVERY, vanish = trail.VANISH,
    core_w = trail.CORE_W, glow_w = trail.GLOW_W,
    r = trail.R, g = trail.G, b = trail.B,
    depth = trail.DEPTH, beam = trail.BEAM, glow = trail.GLOW,
  }
  -- Every field `opts` may override, one at a time: a `pairs` loop would read in
  -- an unspecified order (wfcheck's lockstep note), even though copying values
  -- cannot depend on it.
  for _, k in ipairs({
    "max", "every", "vanish", "core_w", "glow_w", "r", "g", "b", "depth", "beam", "glow",
  }) do
    if opts and opts[k] ~= nil then t[k] = opts[k] end
  end
  -- `trail.DEPTH` cannot be read at load time (see trail.DEPTH above), so the
  -- default is resolved here, in a game frame, where `wa` does exist.
  if t.depth == nil then t.depth = wa.depth.OBJECTS end
  trails[#trails + 1] = t
  live[id] = t
  start_driver(t, owner)
  return t
end

-- Is this round trailed? For attaching to rounds you did not launch yourself.
function trail.has(id)
  return live[id] ~= nil
end

-- The round is gone: stop sampling it and let its trail be shed. Optional -- the
-- driver notices a round that stopped firing frames within STALE game frames --
-- but this starts the fade at once.
function trail.drop(id)
  local t = live[id]
  if t then
    t.live = false
    live[id] = nil
  end
end

-- PX's FillTrail (:1210-1233), for one round's frame. A WA missile's
-- `wa.on.missile_frame` and a Lua actor's own brain both call this with the
-- round's id and its motion for the frame. `tick` is the trail driver's clock,
-- so the sampling stays in game frames on either path.
function trail.sample(id, x, y, vx, vy)
  local t = live[id]
  if not t then return end
  t.seen = tick
  if tick % t.every ~= 0 then return end
  if math.abs(vx) < 0.15 and math.abs(vy) < 0.15 then return end
  local pts = t.pts
  local last = pts[#pts]
  if last
      and (last[1] - x) * (last[1] - x) + (last[2] - y) * (last[2] - y) <= 0.01 then
    return
  end
  pts[#pts + 1] = { x, y }
  if #pts > t.max then table.remove(pts, 1) end
end

local installed = false

-- Register the engine callbacks. Call this from your component's install(ctx):
-- a component's file, and anything it requires, only returns data -- `wa` does
-- not exist yet, which is why nothing above this line touches it, and why
-- `trail.DEPTH` waits for `add` to resolve it.
function trail.install()
  if installed then return end
  installed = true

  -- PX's FillTrail (:1210-1233), on the missile's own game frame. A missile
  -- only counts as filled once it has moved (`phase == "post"`), but `seen`
  -- is refreshed on both phases so a round that is still in the air is never
  -- mistaken for gone.
  wa.on.missile_frame(function(m)
    if m.phase ~= "post" then
      local t = live[m.id]
      if t then t.seen = tick end
      return
    end
    trail.sample(m.id, m.x, m.y, m.vx, m.vy)
  end)

  -- PX's DrawTrail (:1298-1380), from the render callback. `wa.draw.ribbon`
  -- copies its table, so one spec is refilled for every pass of every trail, as
  -- the packs do (electrical.lua:409-440): a table per draw made enough garbage
  -- for a collection inside the draw.
  if wa.on.draw and wa.draw.ribbon then
    local RIBBON = { blend = "add", points = {} }
    local function pass(t, sprite, width)
      local pts, n = t.pts, #t.pts
      if n < 2 then return end -- `if (trailAmount < 2) return;` (:1300)
      RIBBON.sprite, RIBBON.depth = sprite, t.depth
      local rp = RIBBON.points
      for i = 1, n do
        -- PX's t (a 0-based i over n, plus one) floored at 0.1: strength,
        -- texcoord and width in one number.
        local f = i / (n + 1)
        if f < 0.1 then f = 0.1 end
        local p = rp[i]
        if not p then p = {}; rp[i] = p end
        p.x, p.y, p.u, p.width = pts[i][1], pts[i][2], f, f * width
        p.color = (255 << 24) | (math.floor(t.r * f) << 16)
          | (math.floor(t.g * f) << 8) | math.floor(t.b * f)
      end
      for i = #rp, n + 1, -1 do rp[i] = nil end
      wa.draw.ribbon(RIBBON)
    end
    wa.on.draw(function()
      for _, t in ipairs(trails) do
        pass(t, t.beam, t.core_w)
        if t.glow_w > 0 then pass(t, t.glow, t.glow_w) end
      end
    end)
  end
end

return trail
