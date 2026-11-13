-- Rain: layers of falling streaks over the view.
local rain = {}

local TILE = 256 -- pixels, one frame of sprites/rain.png
local SLANT = 3 -- slant per unit of wind (pixels/frame²)
local MAX_SLANT = 1.2
local FADE_IN = 48 -- pixels under the clouds over which the rain fades in

local function hash(i, j)
  local h = (i * 73856093) ~ (j * 19349663)
  return (h ~ (h >> 13)) & 0x7fffffff
end

-- The Rain add-on's settings in `W.kinds.rain`; returns the draw for one frame, or nil without rain.
function rain.install(W)
  local cfg = W.kinds.rain
  if not cfg or cfg.amount <= 0 then return nil end
  local sheet = W.keys["sprites/rain.png"]
  local behind = wa.depth.BEHIND_TERRAIN + 0x1000
  local layers = {
    { scale = 0.5, alpha = 0.45, speed = 7, parallax = 0.55, depth = behind },
    { scale = 0.8, alpha = 0.6, speed = 11, parallax = 0.8, depth = behind - 0x10 },
  }
  local sky = cfg.clouds > 0 and require("lib/sky") or nil
  for _, layer in ipairs(layers) do layer.top = sky and sky.RAIN_TOP end
  -- Heavy rain also falls in front of the land and the worms, behind the water.
  if cfg.amount > 0.5 then
    layers[3] = { scale = 1.3, alpha = 0.2 + 0.6 * (cfg.amount - 0.5), speed = 17, parallax = 1, depth = wa.depth.FRONT,
      top = sky and sky.RAIN_TOP_FRONT }
  end
  local dense = math.min(3, math.floor(cfg.amount * 4))
  local light = 0.5 + 0.5 * cfg.amount
  for _, layer in ipairs(layers) do
    layer.drift, layer.batches = 0, {}
    layer.full = 255 * layer.alpha * light
    for f = 0, 3 do
      layer.batches[f] = { sprite = sheet, frame = f, blend = "alpha", depth = layer.depth, quads = {}, count = 0 }
    end
  end
  local PIECE = { sprite = sheet, frame = 0, blend = "alpha", points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} },
    colors = { 0, 0, 0, 0 }, uv = { 0, 0, 1, 1 } }
  -- The part of cell (x, y, T, slant sx) between world rows ya and yb, its alpha from ka at ya to kb at yb.
  local function piece(layer, f, x, y, T, sx, ya, yb, ka, kb)
    if yb - ya < 0.5 then return end
    local va, vb = (ya - y) / T, (yb - y) / T
    local p, c, uv = PIECE.points, PIECE.colors, PIECE.uv
    p[1][1], p[1][2], p[2][1], p[2][2] = x + sx * va, ya, x + T + sx * va, ya
    p[3][1], p[3][2], p[4][1], p[4][2] = x + T + sx * vb, yb, x + sx * vb, yb
    local ca = (math.floor(layer.a * ka) << 24) | 0xFFFFFF
    local cb = (math.floor(layer.a * kb) << 24) | 0xFFFFFF
    c[1], c[2], c[3], c[4] = ca, ca, cb, cb
    uv[2], uv[4] = va, vb
    PIECE.frame, PIECE.depth = f, layer.depth
    wa.draw.quad(PIECE)
  end
  local slant, last
  return function(st)
    -- How much of the rain is falling now: it fades in and out as the weather changes.
    local shown = st.rain or 1
    if shown <= 0 then last = nil; return end
    local target = math.max(-MAX_SLANT, math.min(MAX_SLANT, st.wind * SLANT * cfg.wind))
    slant = slant and slant + (target - slant) * 0.03 or target
    local step = last and st.now - last or 0
    if step < 0 or step > 50 then step = 0 end
    last = st.now
    for _, layer in ipairs(layers) do
      local a = math.floor(layer.full * shown)
      layer.a, layer.colour = a, (a << 24) | 0xFFFFFF
      local T = TILE * layer.scale
      local fall = st.now * layer.speed
      layer.drift = layer.drift + step * layer.speed * slant
      local ox = st.cx * (1 - layer.parallax) + layer.drift
      local oy = st.cy * (1 - layer.parallax) + fall
      local counts = { [0] = 0, 0, 0, 0 }
      local j0 = math.floor((st.top - oy) / T) - 1
      -- With clouds, the rain comes out of them: nothing above the layer's line.
      local line = layer.top
      if line then j0 = math.max(j0, math.floor((line - oy) / T)) end
      local full = line and line + FADE_IN or -math.huge
      -- No rain under the water: the row across the water line fades out.
      local j1 = math.min(math.floor((st.bottom - oy) / T), math.floor((st.water - oy) / T))
      local sx = T * slant
      for j = j0, j1 do
        local y = oy + j * T
        local x0 = ox + j * sx
        local reach = math.abs(sx)
        -- A cell across the clouds' line or the water line shows only its part between them.
        local cut = y + T > st.water or y < full
        for i = math.floor((st.left - reach - x0) / T) - 1, math.floor((st.right + reach - x0) / T) do
          local h = hash(i, j)
          local f = dense - (h % 3 == 0 and 1 or 0)
          if f >= 0 then
            local x = x0 + i * T
            if cut then
              local bottom = math.min(y + T, st.water)
              if line then
                local ya, yb = math.max(y, line), math.min(bottom, full)
                if yb > ya then piece(layer, f, x, y, T, sx, ya, yb, (ya - line) / FADE_IN, (yb - line) / FADE_IN) end
              end
              piece(layer, f, x, y, T, sx, math.max(y, full), bottom, 1, 1)
            else
              local b = layer.batches[f]
              local n = counts[f]
              local l = b.quads
              l[n + 1], l[n + 2] = x, y
              l[n + 3], l[n + 4] = x + T, y
              l[n + 5], l[n + 6] = x + T + sx, y + T
              l[n + 7], l[n + 8] = x + sx, y + T
              l[n + 9] = layer.colour
              counts[f] = n + 9
            end
          end
        end
      end
      for f = 0, 3 do
        if counts[f] > 0 then
          local b = layer.batches[f]
          b.count = counts[f] // 9
          wa.draw.quads(b)
        end
      end
    end
  end
end

return rain
