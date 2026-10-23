-- Shared digit input and event dispatch. Weapons provide their own actions.
local controls = {}
local actions, order = {}, {}
local installed, last_digit
function controls.register(id, callbacks)
  assert(not actions[id], "duplicate turn control: " .. id)
  actions[id] = callbacks
  order[#order + 1] = callbacks
end
function controls.setup()
  if installed then return end
  installed = true
  local current_worm = require("lib/shared").current_worm
  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FRAME_FINISH then
      for _, callbacks in ipairs(order) do
        if callbacks.frame then callbacks.frame(worm) end
      end
      if not worm.turn then return end
      local digit = wa.world.keys().digit
      local pressed = digit ~= nil and digit ~= last_digit
      last_digit = digit
      if not pressed then return end
      local callbacks = actions[worm.weapon]
      if callbacks and callbacks.choose then callbacks.choose(worm, digit) end
    elseif msg == wa.msg.FIRE_WEAPON then
      local callbacks = actions[worm.weapon]
      if callbacks and callbacks.fire then return callbacks.fire(worm) end
    end
  end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.FIRE_WEAPON } })
  wa.on.turn_end(function()
    for _, callbacks in ipairs(order) do
      if callbacks.finish then callbacks.finish() end
    end
  end)
  if wa.on.hud then
    wa.on.hud(function()
      local worm = current_worm()
      local callbacks = worm and actions[worm.weapon]
      if callbacks and callbacks.hud then callbacks.hud(worm) end
    end)
  end
end
return controls
