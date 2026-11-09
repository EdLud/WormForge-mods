-- Public PX posture/hand data; private module state for each consumer.
local PX_POSTURE = {
  weaponlnk = "wf-lib/px/sprites/px_hold/aim.png", weaponlnku = "wf-lib/px/sprites/px_hold/aimu.png",
  weaponlnkd = "wf-lib/px/sprites/px_hold/aimd.png",
  wthrow = "wf-lib/px/sprites/px_hold/draw.png", wthrowu = "wf-lib/px/sprites/px_hold/drawu.png",
  wthrowd = "wf-lib/px/sprites/px_hold/drawd.png",
}
-- The aim sheets' level frame (16 of 32), for a weapon held at a fixed angle
-- that doesn't aim: on the aim sheets WA's phase is the worm's aim angle, and a
-- placed weapon's worm looked at the ground.
local PX_LEVEL = {
  weaponlnk = "wf-lib/px/sprites/px_hold/level.png", weaponlnku = "wf-lib/px/sprites/px_hold/levelu.png",
  weaponlnkd = "wf-lib/px/sprites/px_hold/leveld.png",
}
local PX_HANDS = {
  "wf-lib/px/sprites/px_hold/hand_rad_lower.png", "wf-lib/px/sprites/px_hold/hand_rad.png", "wf-lib/px/sprites/px_hold/hand_rad_upper.png",
}
return { PX_POSTURE = PX_POSTURE, PX_LEVEL = PX_LEVEL, PX_HANDS = PX_HANDS }
