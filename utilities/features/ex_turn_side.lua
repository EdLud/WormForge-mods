-- ExTurnSide, by reddaz: left and right turn the worm during jumps and flights.

local prev_left = false
local prev_right = false

-- Girders and strikes take left and right for their angle and direction
-- until the click is spent; retreat starts once it is.
local GIRDER_SUBTYPE = 17

local function arrows_aim_the_click(worm)
  if not worm.weapon or wa.world.retreat() > 0 then return false end
  local ok, data = pcall(wa.weapons.data, worm.weapon)
  if not ok then return false end
  return data.fires.as == "strike"
    or (data.fires.as == "special" and data.fires.subtype == GIRDER_SUBTYPE)
end

wa.on.worm_message(function(worm)
  if not worm.turn then return end
  if worm.state == "roping" then return end
  if worm.state == "kamikaze" then return end

  local k = wa.world.keys()

  if k.shift then return end

  local left = k.left and not prev_left
  local right = k.right and not prev_right
  prev_left = k.left
  prev_right = k.right
  if not (left or right) or arrows_aim_the_click(worm) then return end

  if left then
    worm.facing = -1
  end

  if right then
    worm.facing = 1
  end
end, { msgs = { wa.msg.FRAME_FINISH } })
