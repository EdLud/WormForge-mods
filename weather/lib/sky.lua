-- Sky: storm clouds along the top of the view, flashes of lightning and the storm's darkness.
local L = require("wf-lib/lightning")

local sky = {}

local SPACING = 70 -- screen pixels between puffs in a row
local ROWS = 3
local PARALLAX = 0.3 -- how much of the camera's movement the clouds follow
local DRIFT = 12 -- pixels a frame per unit of wind (pixels/frame²)

local function hash(i, j)
  local h = (i * 2654435761) ~ (j * 40503)
  h = h ~ (h >> 15)
  return (h & 0xffff) / 0xffff
end

function sky.install(cfg)
  local g = L.gfx()
  local flat = wa.sprites.key("sprites/flat.png")
  local band_depth = wa.depth.BEHIND_TERRAIN + 0x2000
  local style = { depth = band_depth, dark = { 38, 36, 52 }, alpha = cfg.clouds }
  local puffs = {}
  local drift, last = 0, nil
  local glimmer
  local QUAD = { sprite = flat, frame = 0, points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} }, colors = { 0, 0, 0, 0 } }

  local function cover(st, blend, depth, top, bottom)
    local p = QUAD.points
    p[1][1], p[1][2] = st.left - 2, st.top - 2
    p[2][1], p[2][2] = st.right + 2, st.top - 2
    p[3][1], p[3][2] = st.right + 2, st.bottom + 2
    p[4][1], p[4][2] = st.left - 2, st.bottom + 2
    QUAD.blend, QUAD.depth = blend, depth
    local c = QUAD.colors
    c[1], c[2], c[3], c[4] = top, top, bottom, bottom
    wa.draw.quad(QUAD)
  end

  -- The brightest flash now and where: from this mod's strikes, else a flicker in the clouds.
  local function brightest(st)
    local power, x = 0, nil
    for _, s in ipairs(L.strikes) do
      local p = L.flash(s)
      if p > power then power, x = p, s.sx end
    end
    if power > 0 then return power, x end
    if glimmer and st.now >= glimmer.till then glimmer = nil end
    if not glimmer and cfg.chance > 0 and wa.draw.random() < cfg.chance / 100 * 0.004 then
      glimmer = { x = st.left + wa.draw.random() * st.w, till = st.now + 2 + wa.draw.random() * 5,
        power = 0.25 + 0.3 * wa.draw.random() }
    end
    if glimmer then return glimmer.power * (0.5 + 0.5 * wa.draw.random()), glimmer.x end
    return 0, nil
  end

  return function(st)
    local step = last and st.now - last or 0
    if step < 0 or step > 50 then step = 0 end
    last = st.now
    drift = drift + step * st.wind * DRIFT * cfg.wind
    local power, lx = brightest(st)
    if cfg.clouds > 0 then
      local z = st.zoom
      local spacing = SPACING / z
      -- Far away, the clouds follow the camera most of the way.
      local base = st.cx * (1 - PARALLAX) + drift
      local n = 0
      for row = 0, ROWS - 1 do
        local offset = base + row * spacing * 0.5
        local i0 = math.floor((st.left - spacing * 2 - offset) / spacing)
        local i1 = math.floor((st.right + spacing * 2 - offset) / spacing)
        for i = i0, i1 do
          local r = hash(i, row)
          local breathe = 0.08 * wa.math.sin(st.now * 0.01 + r * 6.28)
          n = n + 1
          local p = puffs[n] or {}
          puffs[n] = p
          p.x = i * spacing + offset + (r - 0.5) * spacing * 0.6
          p.y = st.top + (row * 26 + 10 + hash(i, row + 7) * 18) / z
          p.size = (1.4 + 0.9 * r + breathe - row * 0.15) / z
          p.alpha = (0.75 + 0.25 * hash(i, row + 3)) * (1 - row * 0.12)
        end
      end
      for k = #puffs, n + 1, -1 do puffs[k] = nil end
      local reach = 220 / z
      if power > 0 then
        g.draw_cloud(puffs, lx, st.top + 40 / z, power, reach, 0.6, style)
      else
        g.draw_cloud(puffs, 0, 0, 0, 1, 1, style)
      end
    end
    if power > 0 then
      -- The sky behind the land lights up; the land stays dark against it.
      local a = math.floor(110 * power)
      cover(st, "add", band_depth + 0x100, (a << 24) | 0xB4C8FF, (math.floor(a * 0.3) << 24) | 0xB4C8FF)
    end
    if cfg.darkness > 0 then
      local d = cfg.darkness * (1 - 0.8 * power)
      cover(st, "alpha", wa.depth.FRONT - 1, math.floor(150 * d) << 24, math.floor(100 * d) << 24)
    end
  end
end

return sky
