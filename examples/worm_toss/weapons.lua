-- Battle Axe panel slot. Lua cursor actor (stock cursorr.spr), click-hold to drag.
-- Release with a swing to throw, or with no motion to drop.

local PX = 0x10000
local GRAB = 28 * PX
local CURSOR = { "cursorr", "cursorb", "cursorg", "cursory", "cursorp", "cursorc" }

local function dist2(ax, ay, bx, by)
  local dx = ax - bx
  local dy = ay - by
  return dx * dx + dy * dy
end

local function nearest(x, y)
  local best, best_d
  for _, w in ipairs(wa.worms.all()) do
    local d = dist2(w.x, w.y, x, y)
    if not best_d or d < best_d then
      best, best_d = w, d
    end
  end
  if best and best_d <= GRAB * GRAB then
    return best
  end
end

local function cursor_sprite(worm)
  local t = worm.team or 1
  if t < 1 then
    t = 1
  end
  return CURSOR[((t - 1) % 6) + 1]
end

local live

local function cursor_brain(caster)
  local held
  local hist = {}
  local seen_down = false
  local origin
  return function(a)
    if not caster or caster.weapon ~= "battle_axe" then
      if held then
        held:drop()
      end
      a:despawn()
      live = nil
      return
    end
    local p = wa.world.pointer()
    a.x = p.x
    a.y = p.y
    if not held then
      if p.down then
        held = nearest(p.x, p.y)
        if held then
          origin = { px = p.x, py = p.y, wx = held.x, wy = held.y }
          seen_down = true
          hist = {}
        end
      end
      return
    end
    if p.down then
      seen_down = true
    end
    if seen_down and not p.down then
      local vx, vy = 0, 0
      if #hist >= 2 then
        vx = hist[2].x - hist[1].x
        vy = hist[2].y - hist[1].y
      end
      held:drop()
      held.vx = vx
      held.vy = vy
      held = nil
      origin = nil
      seen_down = false
      hist = {}
      return
    end
    hist[#hist + 1] = { x = p.x, y = p.y }
    if #hist > 2 then
      table.remove(hist, 1)
    end
    if not origin then
      origin = { px = p.x, py = p.y, wx = held.x, wy = held.y }
    end
    held:carry(origin.wx + (p.x - origin.px), origin.wy + (p.y - origin.py))
  end
end

wa.weapons.replace({
  weapon = "battle_axe",
  name = "Worm Toss",
  is_weapon = true,
  on_select = function(sel)
    if live then
      return
    end
    local p = wa.world.pointer()
    live = wa.actors.spawn({
      sprite = cursor_sprite(sel.worm),
      x = p.x,
      y = p.y,
      vx = 0,
      vy = 0,
      gravity = false,
      loop = false,
      collide = false,
      origin = "center",
      owner = sel.worm,
      on = cursor_brain(sel.worm),
    })
  end,
})
