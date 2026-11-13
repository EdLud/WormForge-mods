-- Snow: flakes drifting down behind the land, each with its own place, size, sway and speed.
local snow = {}

snow.SLANT = 8 -- drift per unit of wind (pixels/frame²), in pixels across a pixel fallen
snow.MAX_SLANT = 3
local FADE_IN = 48 -- pixels under the clouds over which the snow fades in
local BUDGET = 1000 -- flakes a frame at most
local LOOK = 3 -- cells looked at per flake drawn, at most: past it the farthest layers go
-- A layer's flakes fall at these factors of its speed: each its own lattice of cells, so neighbours differ.
local CLASSES = { 0.7, 1.0, 1.35 }
local SPREAD = math.sqrt(#CLASSES) -- a class's cells are this much larger, so a layer keeps its density

-- How far the wind slants the snow, as the simulation and the drawing both take it.
function snow.slant(wind, cfg)
  return math.max(-snow.MAX_SLANT, math.min(snow.MAX_SLANT, wind * snow.SLANT * cfg.wind))
end

-- Settings from the Snow add-on in `W.kinds.snow`; returns the draw for one frame, or nil without snow.
function snow.install(W)
  local cfg = W.kinds.snow
  if not cfg or cfg.amount <= 0 then return nil end
  local sheet = W.keys["sprites/flake.png"]
  -- Between the band of clouds and the rain: the clouds hide where it starts, the land covers it.
  local behind = wa.depth.BEHIND_TERRAIN + 0xC00
  local layers = {
    { cell = 56, size = 4, alpha = 0.5, speed = 1.1, parallax = 0.5, sway = 4, depth = behind, frames = { 1, 2 } },
    { cell = 72, size = 5.5, alpha = 0.7, speed = 1.8, parallax = 0.75, sway = 6, depth = behind - 0x10, frames = { 0, 1 } },
    { cell = 96, size = 7, alpha = 0.9, speed = 2.5, parallax = 1, sway = 8, depth = behind - 0x20, frames = { 0, 2 } },
  }
  local line = cfg.clouds > 0 and require("lib/sky").RAIN_TOP or nil
  -- More snow fills more of the cells.
  local fill = 0.25 + 0.75 * cfg.amount
  for k, layer in ipairs(layers) do
    layer.index, layer.drift = k, 0
    layer.batches = {}
    for b = 1, 2 do
      layer.batches[b] = { sprite = sheet, frame = layer.frames[b], blend = "alpha", depth = layer.depth, quads = {}, count = 0 }
    end
  end
  local slant, last
  return function(st)
    local shown = st.snow or 1
    if shown <= 0 then last = nil; return end
    local target = snow.slant(st.wind, cfg)
    slant = slant and slant + (target - slant) * 0.03 or target
    local step = last and st.now - last or 0
    if step < 0 or step > 50 then step = 0 end
    last = st.now
    -- Zoomed far out, the farthest layers go first, then fewer cells by their hash, so the same flakes stay.
    local cells, first = 0, 1
    for _, layer in ipairs(layers) do
      layer.drift = layer.drift + step * layer.speed * slant
      local C = layer.cell * SPREAD
      layer.cells = (st.w / C + 3) * (st.h / C + 3) * #CLASSES
      cells = cells + layer.cells
    end
    while first < #layers and cells * fill > LOOK * BUDGET do
      cells = cells - layers[first].cells
      first = first + 1
    end
    local keep = math.floor(math.min(1, BUDGET / math.max(1, cells * fill)) * fill * 0x10000)
    local floor, sin, now = math.floor, math.sin, st.now
    local top = line and math.max(st.top, line) or st.top
    local bottom = math.min(st.bottom, st.water)
    local fade = line and line + FADE_IN or -math.huge
    for k = first, #layers do
      local layer = layers[k]
      local C = layer.cell * SPREAD
      local half, sway = layer.size / 2, layer.sway
      local alpha = 255 * layer.alpha * shown
      local b1, b2 = layer.batches[1], layer.batches[2]
      local l1, l2, n1, n2 = b1.quads, b2.quads, 0, 0
      local reach = sway + half
      for c, factor in ipairs(CLASSES) do
        local ox = st.cx * (1 - layer.parallax) + layer.drift * factor
        local oy = st.cy * (1 - layer.parallax) + now * layer.speed * factor
        local seed = (k * #CLASSES + c) * 7919
        local i0, i1 = floor((st.left - reach - ox) / C), floor((st.right + reach - ox) / C)
        local j0, j1 = floor((top - half - oy) / C), floor((bottom + half - oy) / C)
        for j = j0, j1 do
          local jy = (j + seed) * 19349663
          for i = i0, i1 do
            local h = (i * 73856093) ~ jy
            h = h ~ (h >> 13)
            h = (h * 0x5bd1e995) & 0xffffffff
            h = h ~ (h >> 15)
            if h >> 16 < keep then
              local y = oy + (j + ((h >> 8) & 255) / 256) * C
              if y > top and y < bottom then
                -- A second hash for the sway, swing, size and brightness of the flake.
                local g = (h * 0x27d4eb2d) & 0xffffffff
                g = g ~ (g >> 15)
                local x = ox + (i + (h & 255) / 256) * C
                  + sway * (0.5 + ((g >> 10) & 63) / 128) * sin(now * (0.02 + ((g >> 16) & 31) / 1000) + (g & 1023) / 163)
                local a = alpha * (0.6 + ((g >> 21) & 63) / 160)
                if y < fade then a = a * (y - line) / FADE_IN end
                if a >= 1 then
                  local s = half * (0.75 + ((g >> 4) & 63) / 126)
                  local colour = ((a // 1) << 24) | 0xFFFFFF
                  if (g >> 27) & 1 == 0 then
                    l1[n1 + 1], l1[n1 + 2], l1[n1 + 3], l1[n1 + 4] = x - s, y - s, x + s, y - s
                    l1[n1 + 5], l1[n1 + 6], l1[n1 + 7], l1[n1 + 8] = x + s, y + s, x - s, y + s
                    l1[n1 + 9] = colour
                    n1 = n1 + 9
                  else
                    l2[n2 + 1], l2[n2 + 2], l2[n2 + 3], l2[n2 + 4] = x - s, y - s, x + s, y - s
                    l2[n2 + 5], l2[n2 + 6], l2[n2 + 7], l2[n2 + 8] = x + s, y + s, x - s, y + s
                    l2[n2 + 9] = colour
                    n2 = n2 + 9
                  end
                end
              end
            end
          end
        end
      end
      if n1 > 0 then b1.count = n1 // 9; wa.draw.quads(b1) end
      if n2 > 0 then b2.count = n2 // 9; wa.draw.quads(b2) end
    end
  end
end

return snow
