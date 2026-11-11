-- Parkour, from PX: the turn's worm wall-jumps on Enter and bunny-hops on Backspace.

local own_time = require("own_time")

local WALL_JUMP = 2 -- PX's WallJumpMultiplier
local BHOP = 3 -- PX's BhopMultiplier
local WALL_REACH, FLOOR_REACH = 20, 30

local WALL_STATES = { jumping = true, sliding = true, tumbling = true }
local BHOP_STATES = { jumping = true, sliding = true, tumbling = true, hit = true, blasted = true }

local parkour = {}

function parkour.new()
  wa._wf_parkour = wa._wf_parkour or {wall={},hop={},frames={},inputs={}}
  local common=wa._wf_parkour
  local wall_delay,bhop_delay=common.wall,common.hop

  local function jumping(worm, vx, vy)
    if worm.state ~= "jumping" then
      worm:jump()
    end
    worm.vx, worm.vy = vx, vy
  end

  local function land(worm, dx, dy)
    local hit = wa.land.trace(worm.x, worm.y, worm.x + dx, worm.y + dy)
    if hit and hit.hit then
      return math.abs(hit.x - worm.x) + math.abs(hit.y - worm.y)
    end
  end

  local function wall_jump(worm)
    if not WALL_STATES[worm.state] then return end
    local right, left = land(worm, WALL_REACH, 0), land(worm, -WALL_REACH, 0)
    if not right and not left then return end
    local side
    if right and left then
      side = right < left and -1 or 1
    else
      side = right and -1 or 1
    end
    local speed = math.abs(worm.vx)
    local vy = math.min(worm.vy, 0) - WALL_JUMP - speed
    local vx = (WALL_JUMP + 1 + speed) * side
    worm.facing = side
    jumping(worm, vx, vy)
  end

  local function bunny_hop(worm)
    if not BHOP_STATES[worm.state] then return end
    if not land(worm, 0, FLOOR_REACH) then return end
    local vy = math.min(worm.vy, 0) - BHOP
    local vx = worm.vx + (BHOP - 1) * worm.facing
    jumping(worm, vx, vy)
  end

  return function(worm, msg)
    if not worm.turn then return end
    local id = worm.id
    local frame=wa.world.frame()
    if msg == wa.msg.FRAME_FINISH then
      if common.frames[id]==frame then return end
      common.frames[id]=frame
      local n = own_time.frames(worm)
      wall_delay[id] = math.max(0, (wall_delay[id] or 0) - n)
      bhop_delay[id] = math.max(0, (bhop_delay[id] or 0) - n)
      local state = worm.state
      if state == "jump_prepare" then bhop_delay[id] = 25 end
      if state == "parachuting" then wall_delay[id] = 10 end
    elseif msg == wa.msg.JUMP then -- Enter
      common.inputs[id]=common.inputs[id] or {}
      if common.inputs[id][msg]==frame then return end
      common.inputs[id][msg]=frame
      if (wall_delay[id] or 0) < 1 then
        wall_jump(worm)
        wall_delay[id] = 15
      end
    elseif msg == wa.msg.JUMP_UP then -- Backspace
      common.inputs[id]=common.inputs[id] or {}
      if common.inputs[id][msg]==frame then return end
      common.inputs[id][msg]=frame
      if (bhop_delay[id] or 0) == 0 then bunny_hop(worm) end
    end
  end
end

function parkour.air_input(worm, msg)
  return (msg == wa.msg.JUMP and WALL_STATES[worm.state])
    or (msg == wa.msg.JUMP_UP and BHOP_STATES[worm.state]) or false
end

return parkour
