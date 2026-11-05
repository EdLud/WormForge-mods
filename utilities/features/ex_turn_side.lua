-- ExTurnSide, by reddaz: left and right turn the worm during jumps,
-- flights and other actions, but not on the rope, in a Kamikaze or while
-- Shift is held. From reddaz's ExTurnSide pack 1.0.1, with his rope and
-- state lock.

local prev_left = false
local prev_right = false

-- Once per worm per frame: the msgs filter skips Lua for every other message.
wa.on.worm_message(function(worm)
  if not worm.turn then return end
  if worm.state == "roping" then return end
  if worm.state == "kamikaze" then return end

  local k = wa.world.keys()
  
  if k.shift then return end
  
  -- Left key pressed:
  if k.left and not prev_left then
    worm.facing = -1
  end
  
  -- Right key pressed: 
  if k.right and not prev_right then
    worm.facing = 1
  end
  
  prev_left = k.left
  prev_right = k.right
end, { msgs = { wa.msg.FRAME_FINISH } })