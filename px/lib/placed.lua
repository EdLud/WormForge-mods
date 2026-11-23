-- An actor whose code puts it where it wants every frame can still be picked
-- up by a tool (the Gravity Gun): `place` puts it there, and `moved` tells
-- the code, on its next frame, whether something else has moved it or given
-- it speed since.

local placed = {}

-- The engine keeps positions in 16.16 fixed point, so a read differs from
-- what was written by up to 1/131072 px; a tool moves things far more.
local EPS = 1 / 1024

function placed.place(a, s, x, y, vx, vy)
  vx, vy = vx or 0, vy or 0
  a.x, a.y, a.vx, a.vy = x, y, vx, vy
  s.placed_x, s.placed_y, s.placed_vx, s.placed_vy = x, y, vx, vy
end

-- true, then the actor's x, y, vx and vy, when something else changed them.
function placed.moved(a, s)
  local px = s.placed_x
  if px == nil then return false end
  local x, y, vx, vy = a.x, a.y, a.vx, a.vy
  if math.abs(x - px) > EPS or math.abs(y - s.placed_y) > EPS
      or math.abs(vx - s.placed_vx) > EPS or math.abs(vy - s.placed_vy) > EPS then
    s.placed_x = nil
    return true, x, y, vx, vy
  end
  return false
end

return placed
