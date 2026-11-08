-- Auto Kill the King: places one king before the first turn, then runs
-- Project X's CKtkControl (scripts/ktk_control.txt).
--
-- Placement is this port's own. The map is cut into fifths; the king goes
-- around the middle of the defenders' edge fifth. It wants a cave: a floor and
-- 150 px of roof over it, measured with two traces (one down for the roof top,
-- one up from the map bottom for the ground's underside). With no cave, the
-- roof is dug; with no room for one, the mirrored edge is tried; a flat map
-- gets the king on the open surface.
--
-- The king itself is PX's terrain stamp (land.Draw of *king.png), so its solid
-- pixels are the win condition, counted every 5 frames as in the baseline.

-- PX's king stamps, by size and by the side of the map they face out from.
local SPRITES = {
  small = { left = "sprites/king/leftsmallking.png", right = "sprites/king/rightsmallking.png" },
  big = { left = "sprites/king/leftbigking.png", right = "sprites/king/rightbigking.png" },
}

local TEAM = { red = 1, blue = 2, green = 3, yellow = 4, purple = 5, cyan = 6 }

local FIFTHS = 5
local ROOF_MIN = 150        -- PX's cave roof
local CARVE_EXTRA = 140     -- a dug cave sits this much deeper than the 150 px roof
local WORM_RAISE = 20       -- worms are placed this far above their spot, not in the land
local CAVE_SIDE = 40        -- dug cave: air either side of the king
local CAVE_HEADROOM = 56    -- dug cave: air above the king, where defenders start
local FLOOR_MIN = 24        -- land left under a dug cave
local CORRIDOR_R = 9        -- floor corridor out of the cave: roomy enough to walk
local TUNNEL_R = 7          -- zig-zag exit radius
local TUNNEL_STEP = 3       -- one dig circle every 3 px
local CHECK_INTERVAL = 5    -- PX checks the king every 5 frames
local MS_PER_FRAME = 20     -- 50 fps lockstep
-- If the king hangs above (or sinks below) its floor, the log line after the
-- stamp says by how much; set the stamp offset here. A sprite anchored at its
-- centre needs DX = box.w / 2 and DY = box.h / 2.
local STAMP_DX, STAMP_DY = 0, 0
local LAYOUT_FRAME = 5      -- lay out the round once WA has placed its worms
local KING_BOX = { small = { w = 20, h = 40 }, big = { w = 40, h = 80 } }
local KING_NAME = "The King"

return function(ctx)
  -- ctx.option raises for a key mod.toml does not declare, so ask safely and
  -- fall back; a new setting works before it is added to mod.toml.
  local function opt(key, fallback)
    if not (ctx and ctx.option) then return fallback end
    local ok, value = pcall(ctx.option, key)
    if ok and value ~= nil then return value end
    return fallback
  end

  local king_size = opt("king_size", "small")
  if not KING_BOX[king_size] then king_size = "small" end
  local box = KING_BOX[king_size]
  local sprites = SPRITES[king_size]
  -- Only the chosen size's pair: WA's sprite slots are shared by every mod.
  wa.assets.load{
    sprites = { sprites.left, sprites.right },
    gpu_prefix = "sprites/king/",
  }
  local side_mode = opt("side", "left")
  local allow_carve = opt("allow_carve", true)
  local move_worms = opt("move_worms", true)
  local attackersTeam = TEAM[opt("attackers_team", "red")] or 1
  local defendersTeam = TEAM[opt("defenders_team", "blue")] or 2
  local timerType = opt("timer_mode", "attack_only") == "defend_and_compensate"
    and "DefendAndCompensate" or "AttackOnly"
  local defenderGainMs = opt("defender_gain_ms", 5)
  local destroyPercent = opt("destruction_percent", 70)
  local defenderInset = opt("defender_inset_px", 250) or 250  -- king and defenders, from the edge fifth
  local showTimer = opt("show_timer", true)
  local showKingHp = opt("show_king_hp", true)

  local size, water
  local initialized, matchOver, winningTeam, winReason = false, false, nil, ""
  local king
  local timerMs = (opt("attack_time_seconds", 300) or 300) * 1000
  local lastWormId = 99
  local frameCheck = 0

  local function px(v) return math.floor(v + 0.5) end

  -- ---------------------------------------------------------------------------
  -- Terrain measurements at one column.
  -- ---------------------------------------------------------------------------

  -- Trace 1, downward: the first solid pixel is the roof top.
  local function surface_at(x)
    local hit = wa.land.trace(x, 0, x, size.h - 1)
    if not hit then return nil end
    return px(hit.y)
  end

  -- Trace 2, upward from the map bottom: the first solid is the ground's
  -- underside, so `bottom - surface` is the whole column's thickness.
  local function ground_bottom(x, top)
    local hit = wa.land.trace(x, size.h - 1, x, top + 1)
    if not hit then return nil end
    return px(hit.y)
  end

  local function first_air(x, y)
    local yy = y
    while yy < size.h and wa.land.solid(x, yy) do yy = yy + 1 end
    if yy >= size.h then return nil end
    return yy
  end

  local function first_solid(x, y)
    local yy = y
    while yy < size.h and not wa.land.solid(x, yy) do yy = yy + 1 end
    if yy >= size.h then return nil end
    return yy
  end

  local function measure(x)
    local r = { x = x }
    r.surface = surface_at(x)
    if not r.surface then r.why = "void" return r end
    r.bottom = ground_bottom(x, r.surface)
    if not r.bottom then r.why = "void" return r end
    r.thickness = r.bottom - r.surface
    r.roofBottom = first_air(x, r.surface)
    if r.roofBottom then
      r.roof = r.roofBottom - r.surface
      r.floorY = first_solid(x, r.roofBottom)
      if r.floorY then r.caveH = r.floorY - r.roofBottom end
    end
    return r
  end

  local function dry(y)
    return not water or y < water - FLOOR_MIN
  end

  local function natural(r)
    return r.roof ~= nil and r.floorY ~= nil
      and r.roof >= ROOF_MIN and r.caveH >= box.h + 8 and dry(r.floorY)
  end

  local function can_carve(r)
    if not r.surface or not r.thickness then return false end
    local floorY = r.surface + ROOF_MIN + CARVE_EXTRA + box.h + CAVE_HEADROOM
    return r.thickness >= ROOF_MIN + CARVE_EXTRA + box.h + CAVE_HEADROOM + FLOOR_MIN
      and floorY + FLOOR_MIN <= size.h - 1 and dry(floorY)
  end

  -- ---------------------------------------------------------------------------
  -- Digging.
  -- ---------------------------------------------------------------------------

  local function dig_line(x0, y0, x1, y1, rad)
    local dx, dy = x1 - x0, y1 - y0
    local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / TUNNEL_STEP))
    for i = 0, steps do
      local t = i / steps
      wa.land.cut{
        x = px(x0 + dx * t), y = px(y0 + dy * t),
        shape = "circle", radius = rad or TUNNEL_R,
      }
    end
  end

  -- PX's map has a winding way in; this one zig-zags up from the hall's edge so
  -- the 150 px of roof over the king itself stays whole.
  local function dig_exit(x0, fromY)
    local x, y = x0, fromY
    local offs = { -10, 8, -12, 10, -6, 12 }
    local i = 1
    for _ = 1, 40 do
      local top = surface_at(x)
      if not top or y <= top + 6 then break end
      local nx, ny = x0 + offs[i], y - 22
      dig_line(x, y, nx, ny)
      x, y = nx, ny
      i = i % #offs + 1
    end
    local top = surface_at(x)
    if top then dig_line(x, y, x, top + 2) end
  end

  local function carve(r)
    local caveTop = r.surface + ROOF_MIN + CARVE_EXTRA
    local floorY = caveTop + box.h + CAVE_HEADROOM
    if floorY + FLOOR_MIN > size.h - 1 or not dry(floorY) then return nil end
    local half = math.floor(box.w / 2) + CAVE_SIDE
    local midY = caveTop + math.floor((box.h + CAVE_HEADROOM) / 2)
    local radius = math.floor((box.h + CAVE_HEADROOM) / 2)
    if radius > 60 then radius = 60 end
    local step = math.max(4, math.floor(radius / 2))
    local lastCx = r.x
    for cx = r.x - half, r.x + half, step do
      wa.land.cut{ x = cx, y = midY, shape = "circle", radius = radius }
      lastCx = cx
    end
    -- The way out starts at the floor, on the edge of the last circle: a flat
    -- corridor along the cave floor out through the end wall, then the zig-zag
    -- climbs from its end. (From the roof it was out of reach.)
    local corridorY = floorY - CORRIDOR_R - 1
    local endX = lastCx + radius + 6
    dig_line(lastCx, corridorY, endX, corridorY, CORRIDOR_R)
    dig_exit(endX, corridorY)
    -- Check the hall from the world itself, not from the roof above it. A map
    -- with air pockets over the cut has a thin "roof" by measure() even though
    -- the hall was dug exactly where planned, and rejecting it left the dug
    -- hall empty while the king and the worms went somewhere else. The king
    -- column needs a floor near the planned one, with open air above it.
    local fs = first_solid(r.x, caveTop + 8)
    if not fs or math.abs(fs - floorY) > 4 or fs - caveTop < box.h + 8 then
      wa.log(string.format("[AutoKTK] carve check failed at x=%d: floor %s, planned %d, cave top %d",
        r.x, tostring(fs), floorY, caveTop))
      return nil
    end
    local after = measure(r.x)
    after.floorY = fs
    return after
  end

  -- ---------------------------------------------------------------------------
  -- Choosing the spot.
  -- ---------------------------------------------------------------------------

  -- Centre of a side's edge fifth, moved `inset` px toward the middle of the
  -- map (never past 40% of the width).
  local function slice_centre(side, inset)
    local fifth = math.floor(size.w / FIFTHS)
    local c = math.floor(fifth / 2) + (inset or 0)
    local limit = math.floor(size.w * 0.4)
    if c > limit then c = limit end
    if side == "left" then return c end
    return size.w - c
  end

  local function find_spot(side)
    local centre = slice_centre(side, defenderInset)
    local offsets = { 0, -12, 12, -24, 24, -36, 36 }
    local thin
    for _, dx in ipairs(offsets) do
      local x = centre + dx
      if x < 4 then x = 4 elseif x > size.w - 5 then x = size.w - 5 end
      local r = measure(x)
      if natural(r) then
        r.side = side
        r.mode = "cave"
        return r
      end
      if can_carve(r) then thin = thin or r end
    end
    if thin then thin.side = side end
    return nil, thin
  end

  local function open_spot(side)
    local centre = slice_centre(side, defenderInset)
    local offsets = { 0, -16, 16, -32, 32 }
    for _, dx in ipairs(offsets) do
      local x = centre + dx
      if x < 4 then x = 4 elseif x > size.w - 5 then x = size.w - 5 end
      local top = surface_at(x)
      if top and top > box.h + 4 then
        return { x = x, side = side, mode = "open", surface = top, floorY = top }
      end
    end
    return nil
  end

  local function place(spot)
    local kx = spot.x - math.floor(box.w / 2)
    local ky = spot.floorY - box.h
    if kx < 0 then kx = 0 end
    if kx + box.w > size.w then kx = size.w - box.w end
    wa.land.stamp{ sprite = sprites[spot.side], frame = 0,
      x = kx + STAMP_DX, y = ky + STAMP_DY }
    spot.kingX, spot.kingY = kx, ky
    -- Gap between the king's feet and the floor: first air below the king's
    -- top is the king's bottom edge when something stands under it.
    local feet = first_air(kx + math.floor(box.w / 2), ky + 2)
    wa.log(string.format("[AutoKTK] king bottom edge at %s, floor at %s (gap %s)",
      tostring(feet), tostring(spot.floorY),
      feet and tostring(spot.floorY - feet) or "?"))
    -- Diagnostics: the pixel under the king's feet should be solid, and the
    -- stamp should have put solid pixels in the box.
    wa.log(string.format("[AutoKTK] stamp at (%d,%d) frame %d; ground under feet: %s; floorY %s",
      kx, ky, wa.world.frame() or -1,
      tostring(wa.land.solid(kx + math.floor(box.w / 2), ky + box.h)),
      tostring(spot.floorY)))
    return kx, ky
  end

  -- ---------------------------------------------------------------------------
  -- Worm spawn points: defenders above the king, attackers on the far edge.
  -- ---------------------------------------------------------------------------

  local function team_worms(team)
    local list = {}
    for _, w in ipairs(wa.worms.all()) do
      if w.team == team and w.hp > 0 then list[#list + 1] = w end
    end
    return list
  end

  -- Free air span around x on row y, so the defenders stay inside the cave.
  local function span_at(x, y)
    local x0, x1 = x, x
    while x0 > 0 and not wa.land.solid(x0 - 1, y) do x0 = x0 - 1 end
    while x1 < size.w - 1 and not wa.land.solid(x1 + 1, y) do x1 = x1 + 1 end
    return x0, x1
  end

  local function spread(list, x0, x1, row, face)
    local n = #list
    if n == 0 then return end
    local span = x1 - x0 - 8
    if span < 0 then span = 0 end
    for i = 1, n do
      local t = (n == 1) and 0.5 or ((i - 1) / (n - 1))
      local x = x0 + 4 + px(span * t)
      list[i]:warp{ x = x, y = row, facing = face }
    end
  end

  local function move_defenders(spot)
    local row = spot.kingY - 2 - WORM_RAISE
    local cx = spot.kingX + math.floor(box.w / 2)
    local x0, x1 = span_at(cx, row)
    -- Only the cave (or a little around the king in the open), never the map.
    local near0, near1 = spot.kingX - 20, spot.kingX + box.w + 20
    if x0 < near0 then x0 = near0 end
    if x1 > near1 then x1 = near1 end
    local face = spot.side == "right" and -1 or 1
    spread(team_worms(defendersTeam), x0, x1, row, face)
  end

  local function move_attackers(kingSide)
    local side = kingSide == "right" and "left" or "right"
    local centre = slice_centre(side)
    local list = team_worms(attackersTeam)
    local n = #list
    if n == 0 then return end
    local face = side == "right" and -1 or 1
    for i = 1, n do
      local t = (n == 1) and 0.5 or ((i - 1) / (n - 1))
      local x = centre - 30 + px(60 * t)
      if x < 4 then x = 4 elseif x > size.w - 5 then x = size.w - 5 end
      local top = surface_at(x) or size.h - 8
      list[i]:warp{ x = x, y = top - 2 - WORM_RAISE, facing = face }
    end
  end

  -- ---------------------------------------------------------------------------
  -- King health (the baseline's half-open box scan).
  -- ---------------------------------------------------------------------------

  local function count_solid(x1, y1)
    local n = 0
    for x = x1, x1 + box.w - 1 do
      for y = y1, y1 + box.h - 1 do
        if wa.land.solid(x, y) then n = n + 1 end
      end
    end
    return n
  end

  local function init_king(spot)
    local kx, ky = spot.kingX, spot.kingY
    local total = count_solid(kx, ky)
    local k = {
      x1 = kx, y1 = ky, x2 = kx + box.w, y2 = ky + box.h,
      totalArea = total, currentArea = total,
      threshold = math.floor(total * (1 - destroyPercent / 100)),
      active = total > 0, destroyed = false, percent = 0,
    }
    if total == 0 then
      wa.log(string.format("[AutoKTK] king box (%d,%d) has no solid pixels; win check off", kx, ky))
    end
    return k
  end

  local function check_king(k)
    if not k or not k.active or k.destroyed then return false end
    local n = count_solid(k.x1, k.y1)
    k.currentArea = n
    if k.totalArea > 0 then
      k.percent = math.floor(((k.totalArea - n) * 100) / k.totalArea)
    end
    if n <= k.threshold then
      k.destroyed = true
      return true
    end
    return false
  end

  -- ---------------------------------------------------------------------------
  -- Win, timer, HUD.
  -- ---------------------------------------------------------------------------

  local function eliminate(losingTeam, winner, reason)
    if matchOver then return end
    matchOver = true
    winningTeam = winner
    winReason = reason
    wa.log(string.format("[AutoKTK] %s; team %d loses", reason, losingTeam))
    for _, w in ipairs(wa.worms.all()) do
      if w.team == losingTeam and w.hp > 0 then w:hurt(w.hp) end
    end
  end

  local function format_time(ms)
    if ms < 0 then ms = 0 end
    local s = math.floor(ms / 1000)
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
  end

  -- ---------------------------------------------------------------------------
  -- Round start: pick the ground, stamp the king, move the worms.
  -- ---------------------------------------------------------------------------

  local function layout()
    size = wa.world.size()
    if not size or size.w <= 0 or size.h <= 0 then return end
    water = wa.world.water()

    local side = side_mode
    if side ~= "left" and side ~= "right" then
      side = wa.random(0, 1) == 0 and "left" or "right"
    end
    local other = side == "left" and "right" or "left"

    local spot, thin = find_spot(side)
    local how = "natural cave"
    if not spot and allow_carve and thin then
      spot, how = carve(thin), "dug cave"
    end
    if not spot then
      local r, thin2 = find_spot(other)
      if r then
        spot, how = r, "natural cave (mirrored)"
        side = other
      elseif allow_carve and thin2 then
        spot, how = carve(thin2), "dug cave (mirrored)"
        side = other
      end
    end
    if not spot then
      spot, how = open_spot(other), "open ground (mirrored)"
      side = other
    end
    if not spot then
      spot, how = open_spot(side), "open ground"
      side = side
    end
    if not spot then
      wa.log("[AutoKTK] no ground found for the king")
      return
    end
    spot.side = side
    local kx, ky = place(spot)
    king = init_king(spot)
    if spot.roof then
      wa.log(string.format("[AutoKTK] king at (%d,%d), %s, roof %d px", kx, ky, how, spot.roof))
    else
      wa.log(string.format("[AutoKTK] king at (%d,%d), %s", kx, ky, how))
    end
    if move_worms then
      move_defenders(spot)
      move_attackers(spot.side)
    end
  end

  wa.on.worm_message(function(worm)
    -- Not on the very first frames: WA is still placing its worms and the
    -- map, so a layout done then can be undone by the engine afterwards.
    if not initialized and (wa.world.frame() or 0) >= LAYOUT_FRAME then
      initialized = true
      local ok, err = pcall(layout)
      if not ok then wa.log("[AutoKTK] layout failed: " .. tostring(err)) end
    end
    if matchOver or not king then return end

    local isNewFrame = worm.id <= lastWormId
    lastWormId = worm.id

    if worm.turn then
      if worm.team == attackersTeam then
        timerMs = timerMs - MS_PER_FRAME
        if timerMs <= 0 then
          timerMs = 0
          eliminate(attackersTeam, defendersTeam, "attack timer expired")
          return
        end
      elseif timerType == "DefendAndCompensate" and worm.team == defendersTeam then
        timerMs = timerMs + defenderGainMs
      end
    end

    if isNewFrame then
      frameCheck = frameCheck + 1
      if frameCheck >= CHECK_INTERVAL then
        frameCheck = 0
        if check_king(king) then
          eliminate(defendersTeam, attackersTeam, KING_NAME .. " destroyed")
        end
      end
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })

  wa.on.hud(function()
    if not initialized or not king then return end
    if showTimer then
      wa.hud.line("Remaining attack time: " .. format_time(timerMs), 14, 40)
    end
    if showKingHp then
      local line
      if not king.active then
        line = KING_NAME .. ": [no solid pixels at the king box]"
      elseif king.destroyed then
        line = KING_NAME .. ": DESTROYED"
      else
        line = string.format("%s HP: %d%%", KING_NAME, math.max(0, 100 - king.percent))
      end
      wa.hud.line(line, 14, 80)
    end
    if matchOver and winningTeam then
      wa.hud.line(string.format("=== TEAM %d WINS (%s) ===", winningTeam, winReason), 14, 120)
    end
  end)
end