-- ExTurnSide, by reddaz: left and right turn the worm during jumps and flights.

local prev_left = false
local prev_right = false

wa.on.worm_message(function(worm)
  if not worm.turn then return end
  if worm.state == "roping" then return end
  if worm.state == "kamikaze" then return end

  local k = wa.world.keys()
  
  if k.shift then return end
  
  if k.left and not prev_left then
    worm.facing = -1
  end
  
  if k.right and not prev_right then
    worm.facing = 1
  end
  
  prev_left = k.left
  prev_right = k.right
end, { msgs = { wa.msg.FRAME_FINISH } })
