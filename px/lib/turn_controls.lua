-- Shared digit input and event dispatch, and the instant-use utilities' Auto-Use.

local controls = {}
local actions, order = {}, {}
-- id -> { instant, auto }: each weapon's data (instant_use, auto_use), from its configure.
local declared = {}
local installed, last_digit
function controls.register(id, callbacks)
  assert(not actions[id], "duplicate turn control: " .. id)
  callbacks.id = id
  actions[id] = callbacks
  order[#order + 1] = callbacks
  if callbacks.hint then require("lib/weapon_hint").register(id, callbacks.hint) end
end
-- A weapon's data, from its configure: instant_use makes it an instant-use
-- utility, and auto_use switches it on at the start of each turn (`on`).
function controls.configure(id, data)
  data = data or {}
  declared[id] = {
    instant = data.instant_use ~= nil,
    auto = data.auto_use == true and data.instant_use == "auto_use",
  }
end
function controls.setup()
  if installed then return end
  installed = true
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
      if not (callbacks and callbacks.fire) then return end
      -- A held worm (the Swim Suit's swimmer) uses instant-use utilities only.
      if worm.taken and not (declared[worm.weapon] or {}).instant then return end
      return callbacks.fire(worm)
    end
  end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.FIRE_WEAPON } })
  -- Auto-Use: each one with it on switches on for the turn's worm, a unit spent.
  wa.on.turn_start(function(ev)
    local worm = ev.worm
    if not worm then return end
    for _, callbacks in ipairs(order) do
      local d = declared[callbacks.id]
      if d and d.auto and callbacks.on and worm:ammo(callbacks.id) ~= 0 and callbacks.on(worm) then
        worm:ammo(callbacks.id, -1)
      end
    end
  end)
  wa.on.turn_end(function()
    for _, callbacks in ipairs(order) do
      if callbacks.finish then callbacks.finish() end
    end
  end)
end
return controls
