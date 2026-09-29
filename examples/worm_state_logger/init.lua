-- Show one live state line for the active worm, and log transitions to file.
local last = {}

-- Provisional WA 3.8.1 names supplied by a user; keep this mapping local to
-- the diagnostic pack until the in-game state values have been checked.
local state_names = {
  [0x65] = "IDLE2",
  [0x66] = "WALK",
  [0x67] = "IDLE",
  [0x68] = "CHARGING",
  [0x69] = "FIRING",
  [0x6A] = "FIRING_2",
  [0x6B] = "FIRING_3",
  [0x6E] = "DRILLING",
  [0x6F] = "TELEPORTING",
  [0x70] = "FIRING_ROPE",
  [0x71] = "TORCHING",
  [0x73] = "ROPE ROLL",
  [0x76] = "GETUP", -- after losing control
  [0x77] = "PREPARE_JUMP / JUMPPREPARE", -- both names were given for 0x77
  [0x78] = "JETPACK",
  [0x79] = "JUMP",
  [0x7A] = "JUMPDOWN", -- msg=0x0C: normal; msg=0x02: from parachute
  [0x7B] = "ROPING",
  [0x7D] = "PARACHUTE",
  [0x7E] = "falling with control",
  [0x7F] = "loss of control / sliding",
  [0x80] = "HIT", -- brief response to fall damage or a gunshot before loss of control
  [0x81] = "HIT_FLYING", -- blasted away by an explosion
}

local function state_name(worm, state)
  return state_names[state] or worm.state or "?"
end

local function display_state(worm)
  local state = worm.state_id
  local address = worm.state_address
  if state == nil or address == nil then return nil end
  return string.format("W%d @0x%08X 0x%02X %s",
    worm.id, address, state, state_name(worm, state))
end

wa.log("worm_state_logger: enabled (HUD and wkLua.log)")

wa.on.worm_message(function(worm, msg)
  local state = worm.state_id
  local address = worm.state_address
  if state == nil or address == nil then return end

  local id = worm.id
  local previous = last[id]
  if previous and previous.state == state and previous.address == address then return end
  last[id] = { state = state, address = address }

  wa.log(string.format(
    "worm_state: worm=%d address=0x%08X state=0x%02X name=%s msg=0x%02X",
    id, address, state, state_name(worm, state), msg))
end)

wa.on.hud(function()
  local line = "Worm state: ?"
  for _, worm in ipairs(wa.worms.all()) do
    if worm.turn then
      line = "Worm state: " .. (display_state(worm) or "?")
      break
    end
  end
  wa.hud.line(line, 14, 10)
end)
