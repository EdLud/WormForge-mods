-- Glow: a faint white glow over settled snow, on the top pixel of each column of lying snow and on each frost spot.
local settle = require("lib/settle")

local glow = {}

local SIZE = 5 -- pixels across the glow round a single pixel; a 2x2 square's is one more
local COLOUR = 0x38FFFFFF -- added over the land, so faint

-- The glow's boxes of chunk c of the map, from the snow as the simulation left it, where its land is still there:
-- x, y, w, h, angle, frame, colour.
function glow.boxes(s, c, list)
  local solid = wa.land.solid
  local n = 0
  local function box(x, y, size)
    list[n + 1], list[n + 2], list[n + 3], list[n + 4] = x, y, size, size
    list[n + 5], list[n + 6], list[n + 7] = 0, 0, COLOUR
    n = n + 7
  end
  for x = c * settle.CHUNK, (c + 1) * settle.CHUNK - 1 do
    local col = s.cols[x]
    if col and col.depth > 0 and solid(x, col.top) then box(x + 0.5, col.top + 0.5, SIZE) end
  end
  for _, spot in ipairs(s.chunks[c] or {}) do
    if solid(spot.x, spot.y) then box(spot.x + spot.w / 2, spot.y + spot.w / 2, SIZE + spot.w - 1) end
  end
  return n // 7
end

-- With snow in play, the draw for one frame: each chunk on screen, its boxes built again when it changed, and one
-- of them again each frame in turn, so the glow leaves land blown away before the simulation's sweep gets there.
function glow.install(W)
  if not W.kinds.snow then return nil end
  -- On the ground: in front of the land, behind the worms and what WA draws over it.
  local brush = wa.draw.brush{ sprite = W.keys["sprites/glow.png"], blend = "add", depth = wa.depth.TERRAIN - 1 }
  local lists, counts, seen = {}, {}, {}
  local turn = 0
  return function(st)
    local s = settle.state
    if not s then return end
    local pad = SIZE + 1
    local c0, c1 = math.floor(st.left - pad) // settle.CHUNK, math.floor(st.right + pad) // settle.CHUNK
    turn = turn + 1
    local again = c0 + turn % (c1 - c0 + 1)
    for c = c0, c1 do
      local changes = s.changes[c] or 0
      if seen[c] ~= changes or c == again then
        lists[c] = lists[c] or {}
        counts[c] = glow.boxes(s, c, lists[c])
        seen[c] = changes
      end
      if counts[c] > 0 then brush:boxes(lists[c], counts[c]) end
    end
  end
end

return glow
