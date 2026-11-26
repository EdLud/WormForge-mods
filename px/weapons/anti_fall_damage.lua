-- Anti Fall Damage: for the turn, a worm falls no faster than 8 pixels a frame, so it lands unhurt and in control.

local ID = "px.anti_fall_damage"
local SOUND = "sounds/anti_fall_damage/fall_protection.wav"
-- WA 3.8.1 turns a jumping, falling or tumbling worm that comes down at 8
-- pixels a frame or more into hit, the spin, with fall damage armed
-- (0x515D1A, the speed as its frame starts). Its landing (0x50DF47) hurts a
-- worm, and makes it get up, only at 8 pixels a frame plus a frame's gravity
-- or more (0x50DFDC, 0x50E1F8). Held just under 8, a worm off a high ledge
-- falls and lands as one off a low one, and a blasted worm lands in control.
local LIMIT = 7.9 -- pixels/frame, downward
local GUARDED = {
  jumping = true, falling = true, jump_falling = true,
  tumbling = true, hit = true, blasted = true, after_rope = true,
}

local weapon = {
  defaults = { crate = { type = "utility" }, instant_use = "auto_use" },
  definition = {
    copy_from = "stock.double_turn_time",
    name = "Anti Fall Damage",
    panel_icon = "sprites/anti_fall_damage/anti_fd_ico.png",
    handling = { remember_selection = false, ends_turn = false, retreat = -1 },
    utility = { effect = "scripted" },
    sounds = { SOUND },
  },
  requires = { "lib/turn_controls" },
}

function weapon.setup()
  local on = {}
  local icon = require("lib/utility_icon")
  local function switch(worm)
    on[worm.id] = not on[worm.id]
    if on[worm.id] then
      wa.sound.play(worm, SOUND)
      icon.on(ID, worm)
    else
      icon.off(ID, worm)
    end
  end
  require("lib/shared").anti_fall_damage_on = function(worm)
    if not on[worm.id] then switch(worm) end
  end
  require("lib/turn_controls").register(ID, {
    fire = switch,
    on = function(worm)
      if on[worm.id] then return false end
      switch(worm)
      return true
    end,
    finish = function()
      on = {}
      icon.off_all(ID)
    end,
    hint = function(worm)
      return "Anti Fall Damage: " .. (on[worm.id] and "ON" or "OFF") .. "\nSpace: on/off"
    end,
  })
  wa.on.worm_message(function(worm)
    if not worm.turn or not on[worm.id] or not GUARDED[worm.state] then return end
    if worm.vy > LIMIT then worm.vy = LIMIT end
  end, { msgs = { wa.msg.FRAME_FINISH } })
end

function weapon.configure(ctx)
  require("lib/turn_controls").configure(ID, ctx.data)
end

return weapon
