-- Fast aim, from Project X: with Shift held, the aim keys move the
-- crosshair at another speed. Every PX Highlander, KAOS and Specialists
-- scheme carries it (its `fireangle` script).
--
-- PX added 0.002 to FireAngle each frame. WA 3.8.1 steps its aim target
-- (+0x24C, `worm.aim_target`) 0x200 a frame, 180/128 degrees, while an aim
-- key is held, and rounds it down to that grid (control_aim, 0x51D100),
-- which made PX's nudge twice the speed going down and nothing going up.
-- Here the speed is in whole native steps: above 100% WA's step is taken
-- more than once a frame, below it some of WA's steps are taken back.
--
-- Notes:
--   * The step is measured, not assumed: each frame the change since the
--     last frame must be exactly one WA step for anything to happen, so
--     weapons that aim in coarse steps (the Blow Torch's 45 degrees) or
--     not at all keep WA's own aim, and a limit WA clamps to stops it.
--   * Shift is the turn player's synchronized key; the step comes from the
--     worm's own aim, so every peer writes the same.

local STEP = 180 / 128  -- WA's aim step, degrees a frame (exact in binary)

return function(pct)
  local state = {}  -- by worm id: { last = degrees, dir = +-STEP or 0, acc = 0..99 }
  local supported   -- this DLL has worm.aim_target

  -- Once per worm per frame: the msgs filter skips Lua for every other message.
  wa.on.worm_message(function(worm)
    if not worm.turn then return end
    if supported == nil then
      local ok, v = pcall(function() return worm.aim_target end)
      supported = ok and type(v) == "number"
      if not supported then
        wa.log("fast aim: this WormForge has no worm.aim_target; fast aim is off")
      end
    end
    if not supported then return end

    local id = worm.id
    if not worm.aiming or not wa.world.keys().shift then
      state[id] = nil
      return
    end

    local t = worm.aim_target
    local s = state[id]
    if not s then
      state[id] = { last = t, dir = 0, acc = 0 }
      return
    end

    local d = t - s.last
    if d ~= STEP and d ~= -STEP then
      -- Still, at a limit, or moved by something else (a weapon switch,
      -- circular aim turning the worm round): wait for WA's next step.
      s.last, s.acc = t, 0
      if d ~= 0 then s.dir = 0 end
      return
    end
    if d ~= s.dir then
      -- A new direction, or WA clamping back what we pushed past its
      -- limit: take the direction on, scale from its next step.
      s.last, s.dir, s.acc = t, d, 0
      return
    end

    s.acc = s.acc + pct
    local steps = s.acc // 100
    s.acc = s.acc % 100
    local want = math.max(-90, math.min(90, t + (steps - 1) * d))
    if want ~= t then worm:input{ aim = want } end
    s.last = want
  end, { msgs = { wa.msg.FRAME_FINISH } })
end
