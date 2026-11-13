-- Sky: clouds along the top of the level, dark for rain and white for snow, lightning flashes and the storm's darkness.
local L = require("wf-lib/lightning")

local sky = {}

local SPACING = 70 -- pixels between puffs in a row
local ROWS = 3
local CLOUD_Y = -400 -- world y of the top row
local ROW_GAP = 26 -- pixels between rows
local DRIFT = 12 -- pixels a frame per unit of wind (pixels/frame²)
local STORM = { 38, 36, 52 }
local SNOW = { 226, 230, 238 }

-- Where the rain comes out of the clouds: inside the band's lower rows, hidden by
-- them; rain drawn in front of the clouds starts under their underside.
sky.RAIN_TOP = CLOUD_Y + ROW_GAP * 2 + 10
sky.RAIN_TOP_FRONT = CLOUD_Y + ROW_GAP * 2 + 110

local function hash(i, j)
  local h = (i * 2654435761) ~ (j * 40503)
  h = h ~ (h >> 15)
  return (h & 0xffff) / 0xffff
end

-- The clouds, flash and darkness of whatever falls, from the add-ons' settings in `W.kinds`.
function sky.install(W)
  local rain, snow = W.kinds.rain, W.kinds.snow
  local NONE = { clouds = 0, wind = 0, darkness = 0, chance = 0 }
  if not (rain or snow) then return nil end
  rain, snow = rain or NONE, snow or NONE
  local g = L.gfx()
  local flat = W.keys["sprites/flat.png"]
  local band_depth = wa.depth.BEHIND_TERRAIN + 0x800
  local style = { depth = band_depth, dark = { STORM[1], STORM[2], STORM[3] }, alpha = 0 }
  local chance = 0
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
    if not glimmer and chance > 0 and wa.draw.random() < chance / 100 * 0.004 then
      glimmer = { x = st.left + wa.draw.random() * st.w, till = st.now + 2 + wa.draw.random() * 5,
        power = 0.25 + 0.3 * wa.draw.random() }
    end
    if glimmer then return glimmer.power * (0.5 + 0.5 * wa.draw.random()), glimmer.x end
    return 0, nil
  end

  return function(st)
    local wet, white = st.rain or 0, st.snow or 0
    local wr, ws = wet * rain.clouds, white * snow.clouds
    local clouds = math.max(wr, ws)
    local share = (wr + ws) > 0 and ws / (wr + ws) or 0
    for i = 1, 3 do style.dark[i] = math.floor(STORM[i] + (SNOW[i] - STORM[i]) * share) end
    style.alpha = clouds
    chance = rain.chance * wet
    local wind = (wet + white) > 0 and (rain.wind * wet + snow.wind * white) / (wet + white) or 0
    local step = last and st.now - last or 0
    if step < 0 or step > 50 then step = 0 end
    last = st.now
    drift = drift + step * st.wind * DRIFT * wind
    local power, lx = brightest(st)
    -- The band stands in the world: only puffs a view can reach are made.
    local band_top, band_bottom = CLOUD_Y - 120, CLOUD_Y + ROW_GAP * ROWS + 120
    if clouds > 0 and st.bottom > band_top and st.top < band_bottom then
      local n = 0
      for row = 0, ROWS - 1 do
        local offset = drift + row * SPACING * 0.5
        local i0 = math.floor((st.left - SPACING * 3 - offset) / SPACING)
        local i1 = math.floor((st.right + SPACING * 3 - offset) / SPACING)
        for i = i0, i1 do
          local r = hash(i, row)
          local breathe = 0.08 * wa.math.sin(st.now * 0.01 + r * 6.28)
          n = n + 1
          local p = puffs[n] or {}
          puffs[n] = p
          p.x = i * SPACING + offset + (r - 0.5) * SPACING * 0.6
          p.y = CLOUD_Y + row * ROW_GAP + hash(i, row + 7) * 18
          p.size = 1.4 + 0.9 * r + breathe - row * 0.15
          p.alpha = (0.75 + 0.25 * hash(i, row + 3)) * (1 - row * 0.12)
        end
      end
      for k = #puffs, n + 1, -1 do puffs[k] = nil end
      if power > 0 then
        g.draw_cloud(puffs, lx, CLOUD_Y + 40, power, 220, 0.6, style)
      else
        g.draw_cloud(puffs, 0, 0, 0, 1, 1, style)
      end
    end
    if power > 0 then
      -- The sky behind the land lights up; the land stays dark against it.
      local a = math.floor(110 * power)
      cover(st, "add", band_depth + 0x100, (a << 24) | 0xB4C8FF, (math.floor(a * 0.3) << 24) | 0xB4C8FF)
    end
    if rain.darkness * wet > 0 then
      local d = rain.darkness * wet * (1 - 0.8 * power)
      cover(st, "alpha", wa.depth.FRONT - 1, math.floor(150 * d) << 24, math.floor(100 * d) << 24)
    end
  end
end

return sky
