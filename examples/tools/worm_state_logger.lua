-- Show one live state line for the active worm, and log transitions to file.

return function()
  local last = {}

  local function describe(worm)
    local state = worm.state_id
    if state == nil then return nil end
    return string.format("W%d 0x%02X %s", worm.id, state, worm.state_label or "?")
  end

  wa.log("worm_state_logger: enabled (HUD and wkLua.log)")

  wa.on.worm_message(function(worm, msg)
    local state = worm.state_id
    if state == nil then return end

    local id = worm.id
    if last[id] == state then return end
    last[id] = state

    wa.log(string.format("worm_state: worm=%d state=0x%02X name=%s msg=0x%02X",
      id, state, worm.state_label or "?", msg))
  end)

  wa.on.hud(function()
    local line = "Worm state: ?"
    for _, worm in ipairs(wa.worms.all()) do
      if worm.turn then
        line = "Worm state: " .. (describe(worm) or "?")
        break
      end
    end
    wa.hud.line(line, 14, 10)
  end)
end
