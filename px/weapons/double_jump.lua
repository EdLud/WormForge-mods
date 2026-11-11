-- Double Jump: switched on for the turn, a worm in mid-jump jumps once more on Enter or Backspace.

local JUMPING = { [0x79] = true, [0x7A] = true }
local FALLING = 0x7E
local GROUNDED = { [0x65] = true, [0x66] = true, [0x67] = true }

local function install(ctx)
  local id = ctx.id
  wa.weapons.replace({
    wep = "weps/double_jump.wep",
    panel_icon = "sprites/double_jump/icon.png",
  })

  local on, armed = false, false

  local function in_jump(worm)
    local s = worm.state_id
    return JUMPING[s] or (s == FALLING and worm.weapon == "px.jump")
  end

  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FRAME_FINISH then
      if on and not armed and worm.turn and GROUNDED[worm.state_id] then
        armed = true
      end
    elseif msg == wa.msg.FIRE_WEAPON then
      if worm.weapon ~= id then
        return
      end
      if on then
        on, armed = false, false
      else
        on, armed = true, true
        worm:ammo(id, -1)
      end
      require("lib/weapon_hint").notice(worm, on and "Double Jump: ON" or "Double Jump: OFF")
      return "eat"
    elseif msg == wa.msg.JUMP or msg == wa.msg.JUMP_UP then
      if not (armed and worm.turn and not worm.taken and in_jump(worm)) then
        return
      end
      armed = false
      worm:jump()
      return "eat"
    end
  end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.FIRE_WEAPON, wa.msg.JUMP, wa.msg.JUMP_UP } })

  wa.on.turn_start(function()
    on, armed = false, false
  end)

end

return { install = install }
