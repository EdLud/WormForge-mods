-- Project X's effect-manager trail: a short ribbon sampled in game frames and
-- drawn with `wa.draw.ribbon`. Consume with `require("wf-lib/effects/trail")`
-- and list `trail.BEAM`/`trail.GLOW` in the component's sprites.
-- See README.md for the sampling and width rules.

local trail = {}

-- PX bullet defaults; `add` copies them or takes the same names in `opts`.
trail.MAX, trail.EVERY, trail.VANISH = 12, 2, 2
trail.CORE_W, trail.GLOW_W = 8.0, 13.0
-- Lateral jitter in pixels and PX's hue cycle for the additive pass.
trail.NOISE, trail.RAINBOW = 0.0, false
trail.R, trail.G, trail.B = 255, 255, 255
-- nil -> `wa.depth.OBJECTS`, resolved inside a game frame.
trail.DEPTH = nil
trail.BEAM = "wf-lib/effects/sprites/px_effects/beam.png"
trail.GLOW = "wf-lib/effects/sprites/px_effects/beam_glow.png"

local trails = {}
local live = {} -- round id -> trail while it is in the air
local driver, tick = nil, 0
-- Frames a live trail may go unsampled; 3 tolerates one skipped actor frame.
local STALE = 3
-- A fixed table of unit noise keeps the wobble identical on every peer: no
-- random numbers are drawn while drawing.
local NOISE = {}
for i = 1, 257 do
  local h = (i * 1103515245 + 12345) % 2147483648
  NOISE[i] = (h / 1073741824) - 1
end

local function rainbow_of(v)
  if v == true then return { speed = 0.012, offset = 0 } end
  if type(v) == "table" then return v end
  return nil
end

-- PX's HueToRGBLocal, centred at 180 so the colour never goes black. `wa.math`
-- is WA's own sine table, so two peers agree on the last bit (lockstep).
local function hue_hex(hue, f)
  hue = hue - math.floor(hue)
  local rad = hue * 6.2831853
  local r = 180 + 75 * wa.math.sin(rad)
  local g = 180 + 75 * wa.math.sin(rad + 2.0943951)
  local b = 180 + 75 * wa.math.sin(rad + 4.1887902)
  r, g, b = math.floor(r * f), math.floor(g * f), math.floor(b * f)
  if r < 0 then r = 0 elseif r > 255 then r = 255 end
  if g < 0 then g = 0 elseif g > 255 then g = 255 end
  if b < 0 then b = 0 elseif b > 255 then b = 255 end
  return (255 << 24) | (r << 16) | (g << 8) | b
end

-- The driver only needs *an* owner; prefer whose turn it is (the usual one)
-- and fall back to any living worm so late blasts still draw.
local function current_worm()
  local first
  for _, w in ipairs(wa.worms.all()) do
    if w.turn then return w end
    if not first and w.hp > 0 then first = w end
  end
  return first
end

-- Event owners can be a zero handle: `ev.worm` wraps 0, which is still a
-- truthy userdata and `or` will not replace it. `wa.actors.spawn` refuses 0.
local function usable(owner)
  return owner ~= nil and (owner.id or 0) ~= 0
end

local function start_driver(t, owner)
  if driver then return true end
  -- Hidden timer; `persist` keeps it alive through a blast so the shed never
  -- freezes. It exits when `trails` empties.
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
            -- Remove the hole; the loop runs backwards so the shift is safe.
            table.remove(trails, i)
            live[v.id] = nil
          end
        end
      end
      if #trails == 0 then driver = nil; a:despawn() end
    end,
  })
  return driver ~= nil
end

-- Trail the round `id`; `opts` overrides any field above for this trail.
function trail.add(id, owner, opts)
  if not usable(owner) then owner = current_worm() end
  if not usable(owner) then return nil end
  local t = {
    id = id, pts = {}, live = true, seen = tick,
    max = trail.MAX, every = trail.EVERY, vanish = trail.VANISH,
    core_w = trail.CORE_W, glow_w = trail.GLOW_W,
    noise = trail.NOISE, rainbow = trail.RAINBOW,
    r = trail.R, g = trail.G, b = trail.B,
    depth = trail.DEPTH, beam = trail.BEAM, glow = trail.GLOW,
  }
  -- Fixed key order; `pairs` would be unordered.
  for _, k in ipairs({
    "max", "every", "vanish", "core_w", "glow_w", "noise", "rainbow",
    "r", "g", "b", "depth", "beam", "glow",
  }) do
    if opts and opts[k] ~= nil then t[k] = opts[k] end
  end
  t.rainbow = rainbow_of(t.rainbow)
  -- Resolve the depth default in a game frame, where `wa` exists.
  if t.depth == nil then t.depth = wa.depth.OBJECTS end
  if not start_driver(t, owner) then return nil end
  trails[#trails + 1] = t
  live[id] = t
  return t
end

-- Is this round trailed? For attaching to rounds you did not launch yourself.
function trail.has(id)
  return live[id] ~= nil
end

-- The round is gone; start its fade now instead of waiting for STALE.
function trail.drop(id)
  local t = live[id]
  if t then
    t.live = false
    live[id] = nil
  end
end

-- PX's FillTrail for one round's frame; both missiles and actors call this.
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

-- Register callbacks from install(ctx); `wa` does not exist at require time.
function trail.install()
  if installed then return end
  installed = true

  -- Fill on the missile's frame; refresh `seen` on both phases so a live round
  -- is never mistaken for gone.
  wa.on.missile_frame(function(m)
    if m.phase ~= "post" then
      local t = live[m.id]
      if t then t.seen = tick end
      return
    end
    trail.sample(m.id, m.x, m.y, m.vx, m.vy)
  end)

  -- PX's DrawTrail. Reuse one ribbon spec: a table per draw made garbage.
  if wa.on.draw and wa.draw.ribbon then
    local RIBBON = { blend = "add", points = {} }
    local function pass(t, sprite, width)
      local pts, n = t.pts, #t.pts
      if n < 2 then return end -- `if (trailAmount < 2) return;` (:1300)
      RIBBON.sprite, RIBBON.depth = sprite, t.depth
      local rp = RIBBON.points
      for i = 1, n do
        -- PX's t: strength, texcoord and width in one number.
        local f = i / (n + 1)
        if f < 0.1 then f = 0.1 end
        local p = rp[i]
        if not p then p = {}; rp[i] = p end
        local x, y = pts[i][1], pts[i][2]
        if t.noise > 0 then
          -- Perpendicular to the local tangent, as PX jitters a reach arc.
          local a = pts[i - 1] or pts[i]
          local b = pts[i + 1] or pts[i]
          local dx, dy = b[1] - a[1], b[2] - a[2]
          local len = math.sqrt(dx * dx + dy * dy)
          if len > 0.0001 then
            local j = NOISE[((i - 1) % 256) + 1] * t.noise
            x, y = x - dy / len * j, y + dx / len * j
          end
        end
        p.x, p.y, p.u, p.width = x, y, f, f * width
        if t.rainbow then
          -- Hue runs along the ribbon as well as with the clock, so a trail
          -- bends through the spectrum instead of being one flat colour.
          p.color = hue_hex(tick * t.rainbow.speed + f * 0.35
            + (t.rainbow.offset or 0), f)
        else
          p.color = (255 << 24) | (math.floor(t.r * f) << 16)
            | (math.floor(t.g * f) << 8) | math.floor(t.b * f)
        end
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
