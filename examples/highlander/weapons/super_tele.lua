-- Highlander: Super Tele. Split from rules.lua by tools/split_highlander.py.
local shared = require("lib/shared")
local fires = shared.fires

-- --------------------------------------------------------------- Super Tele
do
-- PX's FireFinal arms the teleport, the next M_FRAME starts its pose and
-- sound, and M_FRAME moves the worm 50 frames after that. Keep the click
-- from WA's fire context: the live pointer
-- may have moved by the time the worm arrives. Mask 4 is approximated by
-- three overlapping round cuts, centred where PX places them.
fires.teleports = {} -- worm id -> frozen target and elapsed frames

fires.super_tele_click = function(ev)
  local worm = ev.worm
  if worm.hp <= 0 then return end
  local y = ev.y
  if wa.world.cavern() and y < 19 * 0x10000 then y = 19 * 0x10000 end
  local previous = fires.teleports[worm.id]
  if previous and previous.marker then previous.marker:despawn() end
  -- FireWeapon clears WA's planted X for click-only weapons. Keep a fixed
  -- stock planted-X marker at the saved target until the worm arrives instead.
  local marker = wa.actors.spawn({
    owner = worm, x = ev.x, y = y, sprite = "markerr",
    gravity = false, collide = false, drown = false, loop = true,
  })
  fires.teleports[worm.id] = { x = ev.x, y = y, frames = 0, pending = true, marker = marker }
  wa.sound.play(worm, 68, 0) -- PX's M_SETTARGET confirmation
end

wa.on.worm_message(function(worm, msg)
  if msg ~= wa.msg.FRAME_FINISH then return end
  local tele = fires.teleports[worm.id]
  if not tele then return end
  if worm.hp <= 0 then
    tele.marker:despawn()
    fires.teleports[worm.id] = nil
    return
  end
  if tele.pending then
    tele.pending = false
    -- WA's teleport setup clears its activity flag. Do this after the
    -- Lua-handled FireWeapon return restores that flag, as PX's M_FRAME does.
    worm:set_state("teleporting")
    wa.sound.play(worm, 67, 0) -- PX's teleport start
    return
  end
  tele.frames = tele.frames + 1
  if tele.frames < 50 then return end
  tele.marker:despawn()
  fires.teleports[worm.id] = nil
  worm.x, worm.y = tele.x, tele.y
  for _, rise in ipairs({ 0, 10, 22 }) do
    wa.land.dig({ x = tele.x, y = tele.y - rise * 0x10000, radius = 12 })
  end
end, { msgs = { wa.msg.FRAME_FINISH } })
end
