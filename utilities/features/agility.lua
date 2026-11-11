-- From the Agility pack 1.1 (Zed / 0rang3, port by reddaz), as it was.

local own_time = require("wf-lib/own_time")

local STEP      = 0.1 -- per-tick nudge, matches C's 0.1
local STEP_LOWG = 0.03 -- up-nudge while the world's gravity is changed
local LIMIT     = 3 -- matches C's SpX/SpY <= 3 cap

local ALLOWED = {
  [0x6E] = true, -- WS_DRILLING
  [0x73] = true, -- WS_AFTERROPE
  [0x79] = true, -- WS_JUMP
  [0x7E] = true, -- WS_JUMP
  [0x7F] = true, -- WS_SLIDING
  [0x80] = true, -- WS_FLYING
  [0x81] = true, -- WS_POWERFLY
}

local match_gravity -- the world's gravity at the match's first frame

wa.on.worm_message(function(worm)
  match_gravity = match_gravity or wa.world.gravity()
  if not worm.turn then return end

  local state = worm.state_id
  if not state or not ALLOWED[state] then return end

  local k = worm.keys
  local up_step = wa.world.gravity() == match_gravity and STEP or STEP_LOWG

  for _ = 1, own_time.frames(worm) do
    if k.up and worm.vy >= -LIMIT then
      worm.vy = worm.vy - up_step
    end
    if k.down and worm.vy <= LIMIT then
      worm.vy = worm.vy + STEP
    end
    if k.left and worm.vx >= -LIMIT then
      worm.vx = worm.vx - STEP
    end
    if k.right and worm.vx <= LIMIT then
      worm.vx = worm.vx + STEP
    end
  end
end, { msgs = { wa.msg.FRAME_FINISH } })
