-- Rain: layers of falling streaks over the view.
local rain = {}

local TILE = 256 -- pixels, one frame of sprites/rain.png
local SLANT = 3 -- slant per unit of wind (pixels/frame²)
local MAX_SLANT = 1.2

local function hash(i, j)
  local h = (i * 73856093) ~ (j * 19349663)
  return (h ~ (h >> 13)) & 0x7fffffff
end

-- `cfg.rain` 0..1; returns the draw for one frame, or nil without rain.
function rain.install(cfg)
  if cfg.rain <= 0 then return nil end
  local sheet = wa.sprites.key("sprites/rain.png")
  local behind = wa.depth.BEHIND_TERRAIN + 0x1000
  local layers = {
    { scale = 0.5, alpha = 0.45, speed = 7, parallax = 0.55, depth = behind },
    { scale = 0.8, alpha = 0.6, speed = 11, parallax = 0.8, depth = behind - 0x10 },
  }
  -- Heavy rain also falls in front of the land and the worms, behind the water.
  if cfg.rain > 0.5 then
    layers[3] = { scale = 1.3, alpha = 0.2 + 0.6 * (cfg.rain - 0.5), speed = 17, parallax = 1, depth = wa.depth.FRONT }
  end
  local dense = math.min(3, math.floor(cfg.rain * 4))
  local light = 0.5 + 0.5 * cfg.rain
  for _, layer in ipairs(layers) do
    layer.drift, layer.batches = 0, {}
    local a = math.floor(255 * layer.alpha * light)
    layer.colour = (a << 24) | 0xFFFFFF
    for f = 0, 3 do
      layer.batches[f] = { sprite = sheet, frame = f, blend = "alpha", depth = layer.depth, quads = {}, count = 0 }
    end
  end
  local FADE = { sprite = sheet, frame = 0, blend = "alpha", points = { {0, 0}, {0, 0}, {0, 0}, {0, 0} }, colors = { 0, 0, 0, 0 } }
  local slant, last
  return function(st)
    local target = math.max(-MAX_SLANT, math.min(MAX_SLANT, st.wind * SLANT * cfg.wind))
    slant = slant and slant + (target - slant) * 0.03 or target
    local step = last and st.now - last or 0
    if step < 0 or step > 50 then step = 0 end
    last = st.now
    for _, layer in ipairs(layers) do
      local T = TILE * layer.scale
      local fall = st.now * layer.speed
      layer.drift = layer.drift + step * layer.speed * slant
      local ox = st.cx * (1 - layer.parallax) + layer.drift
      local oy = st.cy * (1 - layer.parallax) + fall
      local counts = { [0] = 0, 0, 0, 0 }
      local j0 = math.floor((st.top - oy) / T) - 1
      -- No rain under the water: the row across the water line fades out.
      local j1 = math.min(math.floor((st.bottom - oy) / T), math.floor((st.water - oy) / T))
      local sx = T * slant
      for j = j0, j1 do
        local y = oy + j * T
        local x0 = ox + j * sx
        local reach = math.abs(sx)
        local fading = y + T > st.water
        for i = math.floor((st.left - reach - x0) / T) - 1, math.floor((st.right + reach - x0) / T) do
          local h = hash(i, j)
          local f = dense - (h % 3 == 0 and 1 or 0)
          if f >= 0 then
            local x = x0 + i * T
            if fading then
              local p, c = FADE.points, FADE.colors
              p[1][1], p[1][2], p[2][1], p[2][2] = x, y, x + T, y
              p[3][1], p[3][2], p[4][1], p[4][2] = x + T + sx, y + T, x + sx, y + T
              c[1], c[2], c[3], c[4] = layer.colour, layer.colour, 0xFFFFFF, 0xFFFFFF
              FADE.frame, FADE.depth = f, layer.depth
              wa.draw.quad(FADE)
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
