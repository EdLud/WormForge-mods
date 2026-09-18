-- Overlay stock grenade. Extra bounce / wind / HUD are Lua, not native options.
--
-- gravity_before writes entity+0x5C so stock apply_projectile_gravity applies
-- cm.wind_bias * wind_scale. gravity_after sees velocity after that leaf.
-- A floor bounce (from CollisionManager__rope, later in the tick) shows up
-- next gravity call as vy reversing from a downward fall.
--
-- Enter/Backspace are stock Jump/JumpUp and already go through lockstep.
-- This pack observes them and does not swallow. Use an anchored scheme if
-- you do not want the worm to jump.

wa.weapons.replace({
  weapon = "grenade",
  name = "Super Bounce",
  params = {
    bounce_pct = 100,
  },
})

local prev_vy = {}
local bounces = {}
local dial = 0
local FALL = 2 * 0x10000

wa.on.gravity_before(function(p)
  if p.wind_scale == 0 then
    p.wind_scale = 0x10000
  end
end)

wa.on.gravity_after(function(p)
  local last = prev_vy[p.id]
  if last and last > FALL and p.vy < 0 then
    bounces[p.id] = (bounces[p.id] or 0) + 1
    p.vy = p.vy + p.vy // 8
  end
  prev_vy[p.id] = p.vy
end)

wa.on.worm_message(function(_worm, msg)
  if msg == wa.msg.JUMP then
    dial = dial + 1
  elseif msg == wa.msg.JUMP_UP then
    dial = dial - 1
  end
end)

wa.on.hud(function()
  local n = 0
  for _, c in pairs(bounces) do
    if c > n then
      n = c
    end
  end
  wa.hud.line("bounces " .. n .. "  dial " .. dial)
end)
