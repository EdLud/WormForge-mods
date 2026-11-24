-- Parkour: parkour for the turn: Enter kicks the worm off a wall, Backspace bunny-hops it.

local kick = {}

local weapon = {
  defaults = {instant_use="auto_use"},
  definition = {
    copy_from = "stock.double_turn_time",
    name = "Parkour",
    panel_icon = "sprites/parkour/parkour_ico.png",
    handling = {remember_selection=false,ends_turn=false,retreat=3000},
    utility = {effect="scripted"},
    sounds = {"sounds/parkour/parkour_snd.wav"},
  },
  requires = {"lib/turn_controls"},
}

function weapon.setup()
  local enabled = {}
  local parkour = require("wf-lib/parkour")
  local movement
  local icon = require("lib/utility_icon")
  local function on(worm)
    enabled[worm.id] = true
    wa.sound.play(worm, "sounds/parkour/parkour_snd.wav")
    icon.on("px.parkour", worm)
  end
  require("lib/shared").parkour_on = function(worm)
    if not enabled[worm.id] then on(worm) end
  end
  require("lib/turn_controls").register("px.parkour", {
    fire = function(worm)
      if enabled[worm.id] then
        enabled[worm.id] = nil
        icon.off("px.parkour", worm)
      else
        on(worm)
      end
    end,
    on = function(worm)
      if enabled[worm.id] then return false end
      on(worm)
      return true
    end,
    finish = function()
      enabled = {}
      icon.off_all("px.parkour")
    end,
    hint = function(worm)
      return "Parkour: " .. (enabled[worm.id] and "ON" or "OFF") .. "\nSpace: on/off\nEnter: wall-jump\nBackspace: hop"
    end,
  })
  wa.on.worm_message(function(worm, msg)
    if not worm.turn or not enabled[worm.id] or worm.hp <= 0 then return end
    movement = movement or parkour.new(kick)
    local airborne = parkour.air_input(worm, msg)
    movement(worm, msg)
    if airborne then return "eat" end
  end, {msgs={wa.msg.FRAME_FINISH,wa.msg.JUMP,wa.msg.JUMP_UP}})
end

function weapon.configure(ctx)
  require("lib/turn_controls").configure("px.parkour", ctx.data)
  kick.wall_jump = ctx.option("wall_jump")
  kick.carry_speed = ctx.option("carry_speed")
end

return weapon
