-- Double Jump: switched on for the turn, a worm in mid-jump jumps once more on Enter or Backspace.

local JUMPING = { jumping = true, jump_falling = true }
local GROUNDED = { standing = true, walking = true, ready = true }

local function install(ctx)
  local id = ctx.id
  local shared = require("lib/shared")
  local controls = require("lib/turn_controls")
  local icon = require("lib/utility_icon")
  wa.weapons.replace({
    wep = "weps/double_jump.wep",
    panel_icon = "sprites/double_jump/icon.png",
  })

  -- from_water: out of the water on the Swim Suit, in WA's fall.
  local on, armed, from_water = false, false, false

  local function in_jump(worm)
    local s = worm.state
    return JUMPING[s] or (s == "falling" and (from_water or worm.weapon == "px.jump"))
  end

  -- A swimmer that jumps out gets its second jump again, as Project X's,
  -- idle in the water, did.
  shared.left_water = function(worm)
    if on and worm.turn then
      armed, from_water = true, true
    end
  end

  local function switch_on(worm)
    on, armed = true, true
    -- On for the turn, whichever worm has it: the team's.
    icon.on(id, worm.team)
    require("lib/weapon_hint").notice(worm, "Double Jump: ON")
  end
  controls.register(id, {
    fire = function(worm)
      if on then
        on, armed, from_water = false, false, false
        icon.off_all(id)
        require("lib/weapon_hint").notice(worm, "Double Jump: OFF")
      else
        switch_on(worm)
        worm:ammo(id, -1)
      end
      return "eat"
    end,
    on = function(worm)
      if on then return false end
      switch_on(worm)
      return true
    end,
    finish = function()
      on, armed, from_water = false, false, false
      icon.off_all(id)
    end,
  })
  controls.configure(id, ctx.data)
  controls.setup()

  wa.on.worm_message(function(worm, msg)
    if msg == wa.msg.FRAME_FINISH then
      if on and worm.turn and GROUNDED[worm.state] then
        armed, from_water = true, false
      end
    elseif msg == wa.msg.JUMP or msg == wa.msg.JUMP_UP then
      if not (armed and worm.turn and not worm.taken and in_jump(worm)) then
        return
      end
      armed, from_water = false, false
      worm:jump()
      return "eat"
    end
  end, { msgs = { wa.msg.FRAME_FINISH, wa.msg.JUMP, wa.msg.JUMP_UP } })
end

return { defaults = { instant_use = "auto_use" }, install = install }
