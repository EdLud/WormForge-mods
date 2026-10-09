-- Shotgun is only the panel slot. Selecting it turns the owner into the POOZ
-- runner (Lua actor). A/D move, W jumps (again in air for the flip), Shift sprints.
-- Switch weapon to drop out.

local PX = 0x10000
local HW = 6 * PX
local BOX_H = 16 * PX
local RUN = 103219
local SPRINT = 149094
local AIR = 3932
local FRICTION = 1638
local SKID = 7209
local ACCEL = 5898
local GRAV = 0x3D70
local MAX_FALL = 406323
local JUMP = -363725
local JUMP2 = -419430
local COYOTE = 6
local JUMP_BUF = 7
local SLOPE = 12
local LAND_VY = 91750

local live = {}

local function abs(v)
  if v < 0 then
    return -v
  end
  return v
end

local function sign(v)
  if v > 0 then
    return 1
  end
  if v < 0 then
    return -1
  end
  return 0
end

local function approach(v, target, rate)
  if v < target then
    v = v + rate
    if v > target then
      return target
    end
    return v
  end
  v = v - rate
  if v < target then
    return target
  end
  return v
end

local function friction(v, amount)
  if abs(v) <= amount then
    return 0
  end
  return v - sign(v) * amount
end

local function blocked(x, y)
  local l = x - HW
  local r = x + HW - PX
  local mid = y - BOX_H // 2
  local top = y - BOX_H
  return wa.land.solid(l, y)
    or wa.land.solid(r, y)
    or wa.land.solid(x, y)
    or wa.land.solid(l, mid)
    or wa.land.solid(r, mid)
    or wa.land.solid(l, top)
    or wa.land.solid(r, top)
    or wa.land.solid(x, top)
end

local function on_floor(x, y)
  local l = x - 2 * PX
  local r = x + 2 * PX
  return wa.land.solid(x, y + PX)
    or wa.land.solid(l, y + PX)
    or wa.land.solid(r, y + PX)
end

local function unstick(x, y)
  if not blocked(x, y) then
    return x, y
  end
  for up = 1, SLOPE do
    if not blocked(x, y - up * PX) then
      return x, y - up * PX
    end
  end
  return x, y
end

-- Glue to dirt within SLOPE pixels so gentle grades do not pop into air.
local function snap_floor(x, y)
  if blocked(x, y) then
    return x, y, false
  end
  for d = 0, SLOPE do
    local ny = y + d * PX
    if d > 0 and blocked(x, ny) then
      return x, ny - PX, true
    end
    if on_floor(x, ny) then
      return x, ny, true
    end
  end
  return x, y, false
end

-- PNG strips are 15fps. Ground clips step every other tick so Walk/Run/Land
-- actually read. FrontFlip stays at 15fps (matches POOZ ~3 ticks/frame).
local function set_clip(a, st, name)
  if st.anim ~= name then
    st.anim = name
    st.clock = 0
    a:look("sprites/" .. name)
    if name == "FrontFlip" then
      for _ = 1, 13 do
        a:advance()
      end
    end
    return
  end
  st.clock = st.clock + 1
  local slow = name == "Idle"
    or name == "Walk"
    or name == "Run"
    or name == "Sprint"
    or name == "Land"
  if slow and st.clock % 2 ~= 0 then
    return
  end
  a:advance()
end

local function restore(worm, a)
  live[worm.id] = nil
  if a then
    worm.x = a.x
    worm.y = a.y
  end
  worm.visible = true
  worm:drop()
end

local function brain(worm)
  local st = {
    anim = "Idle",
    clock = 0,
    jumps = 2,
    coyote = 0,
    jump_buf = 0,
    prev_jump = false,
    flipping = false,
    flip_clock = 0,
    land = 0,
    gait = 0,
    grounded = true,
  }
  return function(a)
    if worm.weapon ~= "shotgun" or a:in_water() then
      restore(worm, a)
      a:despawn()
      return
    end

    local k = wa.world.keys()
    if k.jump and not st.prev_jump then
      st.jump_buf = JUMP_BUF
    elseif st.jump_buf > 0 then
      st.jump_buf = st.jump_buf - 1
    end
    st.prev_jump = k.jump

    local left = k.left and not k.right
    local right = k.right and not k.left
    local vx = a.vx
    local vy = a.vy
    local x = a.x
    local y = a.y

    if st.grounded and vy >= 0 then
      st.coyote = COYOTE
      st.jumps = 2
      st.flipping = false
    elseif st.coyote > 0 then
      st.coyote = st.coyote - 1
    end

    if st.jump_buf > 0 and st.jumps > 0 then
      if st.jumps >= 2 then
        vy = JUMP
        st.grounded = false
        st.coyote = 0
        st.jump_buf = 0
        st.jumps = st.jumps - 1
        st.land = 0
        st.flipping = false
        set_clip(a, st, "JumpRise")
      elseif not st.grounded then
        vy = JUMP2
        st.grounded = false
        st.coyote = 0
        st.jump_buf = 0
        st.jumps = st.jumps - 1
        st.land = 0
        st.flipping = true
        st.flip_clock = 0
        set_clip(a, st, "FrontFlip")
      end
    end

    if left or right then
      local dir = right and 1 or -1
      a.facing = dir
      if st.grounded then
        local cap = k.shift and SPRINT or RUN
        if vx == 0 or sign(vx) == dir then
          if abs(vx) < cap then
            vx = approach(vx, dir * cap, ACCEL)
          else
            vx = friction(vx, 1966)
          end
        else
          vx = friction(vx, SKID)
        end
      else
        local cap = RUN
        if abs(vx) > cap then
          cap = abs(vx)
        end
        local nxt = vx + dir * AIR
        if abs(nxt) <= cap or sign(nxt) ~= sign(vx) then
          vx = nxt
        end
      end
    elseif st.grounded then
      vx = friction(vx, FRICTION)
    end

    local was = st.grounded
    local fall = vy
    x, y = unstick(x, y)
    local glued = st.grounded or st.coyote > 0
    if glued and vy >= 0 then
      local ok
      x, y, ok = snap_floor(x, y)
      if ok then
        vy = 0
        st.grounded = true
      end
    end
    if st.grounded and vy >= 0 and on_floor(x, y) then
      vy = 0
    else
      vy = vy + GRAV
      if vy > MAX_FALL then
        vy = MAX_FALL
      end
    end

    st.grounded = false
    local dist = abs(vx)
    local steps = dist // PX
    if steps < 1 then
      steps = 1
    end
    local sx = vx // steps
    for _ = 1, steps do
      local nx = x + sx
      if not blocked(nx, y) then
        x = nx
      else
        local stepped = false
        for up = 1, SLOPE do
          if not blocked(nx, y - up * PX) then
            x = nx
            y = y - up * PX
            stepped = true
            break
          end
        end
        if not stepped then
          vx = 0
          break
        end
      end
    end

    if vy >= 0 and (was or st.coyote > 0) then
      local ok
      x, y, ok = snap_floor(x, y)
      if ok then
        vy = 0
        st.grounded = true
      end
    end

    if not st.grounded then
      dist = abs(vy)
      steps = dist // PX
      if steps < 1 then
        steps = 1
      end
      local sy = vy // steps
      for _ = 1, steps do
        local ny = y + sy
        if not blocked(x, ny) then
          y = ny
        elseif sy > 0 then
          vy = 0
          st.grounded = true
          break
        else
          vy = 0
          break
        end
      end
      if not st.grounded and vy >= 0 then
        local ok
        x, y, ok = snap_floor(x, y)
        if ok then
          vy = 0
          st.grounded = true
        else
          st.grounded = on_floor(x, y)
        end
      end
    end

    if st.grounded and not was and fall > LAND_VY then
      st.land = 16
    end
    if st.land > 0 then
      st.land = st.land - 1
    end

    a.x = x
    a.y = y
    a.vx = vx
    a.vy = vy
    worm:carry(x, y)

    local moving = abs(vx) > 22938
    if not st.grounded then
      st.gait = 0
      if st.flipping or st.anim == "FrontFlip" then
        set_clip(a, st, "FrontFlip")
        st.flip_clock = st.flip_clock + 1
        if vy > 0 and st.flip_clock >= 24 then
          st.flipping = false
          set_clip(a, st, "JumpFall")
        end
      elseif vy < -52429 then
        set_clip(a, st, "JumpRise")
      elseif vy > 52429 then
        set_clip(a, st, "JumpFall")
      else
        set_clip(a, st, "JumpMid")
      end
    elseif st.land > 0 then
      st.gait = 0
      set_clip(a, st, "Land")
    elseif moving then
      local spd = abs(vx)
      if k.shift then
        st.gait = 32
        if spd > SPRINT - 22938 then
          set_clip(a, st, "Sprint")
        else
          set_clip(a, st, "Run")
        end
      else
        st.gait = st.gait + 1
        if st.gait < 40 then
          set_clip(a, st, "Walk")
        else
          set_clip(a, st, "Run")
        end
      end
    else
      st.gait = 0
      set_clip(a, st, "Idle")
    end
  end
end

wa.weapons.replace({
  weapon = "shotgun",
  name = "POOZ",
  sprites = {
    "sprites/Idle",
    "sprites/Run",
    "sprites/Walk",
    "sprites/Sprint",
    "sprites/JumpRise",
    "sprites/JumpMid",
    "sprites/JumpFall",
    "sprites/FrontFlip",
    "sprites/Land",
  },
  on_select = function(sel)
    local worm = sel.worm
    if live[worm.id] then
      return
    end
    live[worm.id] = true
    worm.visible = false
    worm:carry(worm.x, worm.y)
    wa.actors.spawn({
      sprite = "sprites/Idle",
      origin = "bottom",
      x = worm.x,
      y = worm.y,
      vx = 0,
      vy = 0,
      gravity = false,
      collide = false,
      loop = false,
      owner = worm,
      on = brain(worm),
    })
  end,
})
