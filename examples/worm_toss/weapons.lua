-- Worm Toss: WA land-cursor MODE + wa.cursor actor + click eaten at source.
--
-- on_select.cursor = true -> WA enters land-cursor mode: the mouse moves the
--                   world cursor (World+0x7380/84), NOT the camera. Camera
--                   scrolls only at the screen edge. Any map point reachable.
-- eat_fire = true -> Rust eats the lockstep click (TeamEntity msg 0x32) for
--                   this slot: no X marker, no launch anim, no turn end, and
--                   the cursor keeps moving. WA's own cursor draw is skipped.
-- wa.cursor.spawn -> the only cursor on screen: a Lua actor wearing the stock
--                   team-colour cursor (what Teleport shows), snapped to
--                   wa.world.pointer() natively every frame before `on` runs.
--                   Grab/drag/throw use the actor position.

local PX = 0x10000
local GRAB_R2 = (48 * PX) * (48 * PX)

local owner_id
local live
local held
local hist = {}
local origin
local prev_down = false

local function nearest_target(x, y)
  local best, best_d
  for _, w in ipairs(wa.worms.all()) do
    if w.id ~= owner_id then
      local dx = w.x - x
      local dy = w.y - y
      local d = dx * dx + dy * dy
      if d <= GRAB_R2 and (not best_d or d < best_d) then
        best, best_d = w, d
      end
    end
  end
  return best
end

local function release()
  if not held then
    return
  end
  local vx, vy = 0, 0
  if #hist >= 2 then
    vx = hist[#hist].x - hist[1].x
    vy = hist[#hist].y - hist[1].y
  end
  held:drop()
  held.vx = vx
  held.vy = vy
  wa.log(string.format("worm_toss throw vx=%d vy=%d", vx // PX, vy // PX))
  held = nil
  origin = nil
  hist = {}
end

local function try_grab(x, y)
  if held then
    return true
  end
  local w = nearest_target(x, y)
  if not w then
    return false
  end
  held = w
  origin = { px = x, py = y, wx = w.x, wy = w.y }
  hist = {}
  wa.log(string.format("worm_toss grab id=%s", tostring(w.id)))
  return true
end

-- a.x / a.y are already on the pointer (cursor actor); only the button is read.
local function tick(a)
  local down = wa.world.pointer().down

  if held then
    hist[#hist + 1] = { x = a.x, y = a.y }
    if #hist > 4 then
      table.remove(hist, 1)
    end
    if not origin then
      origin = { px = a.x, py = a.y, wx = held.x, wy = held.y }
    end
    held:carry(origin.wx + (a.x - origin.px), origin.wy + (a.y - origin.py))
    if prev_down and not down then
      release()
    end
  elseif down and not prev_down then
    try_grab(a.x, a.y)
  end

  prev_down = down
end

wa.weapons.replace({
  weapon = "battle_axe",
  name = "Worm Toss",
  is_weapon = true,
  eat_fire = true,
  on_select = {
    -- Land-cursor MODE: mouse moves the world cursor, not the camera.
    cursor = true,
    on = function(sel)
      owner_id = sel.worm.id
      if live then
        return
      end
      -- WA parked the land cursor on the worm at select; sel.x/y is that.
      live = wa.cursor.spawn({
        owner = sel.worm,
        x = sel.x,
        y = sel.y,
        on = tick,
      })
      wa.log(string.format("worm_toss cursor actor at %#x,%#x", sel.x, sel.y))
    end,
  },
  -- Lockstep click (eaten in Rust). Grab if free, throw if holding.
  on_click = function(click)
    if held then
      release()
    else
      try_grab(click.x, click.y)
    end
  end,
})
