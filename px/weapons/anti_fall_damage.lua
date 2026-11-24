-- Anti Fall Damage: for the turn, a fast-flying worm lands on its feet, unhurt and in control.

local ID = "px.anti_fall_damage"
local SOUND = "sounds/anti_fall_damage/fall_protection.wav"
local FAST = 8 -- pixels/frame
-- The flights that don't land softly. Falling and jumping already land
-- unhurt at any speed (WA 3.8.1's collision table 0x50E4C0 sends both to
-- 0x50DD14), so a fast worm is moved into falling: it stays in the air,
-- where it can still fire, and takes no walking.
local GUARDED = {
  jump_falling = true, tumbling = true, hit = true, blasted = true, after_rope = true,
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
    if math.abs(worm.vx) > FAST or math.abs(worm.vy) > FAST then worm:set_state("falling") end
  end, { msgs = { wa.msg.FRAME_FINISH } })
end

function weapon.configure(ctx)
  require("lib/turn_controls").configure(ID, ctx.data)
end

return weapon
