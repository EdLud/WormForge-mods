-- Trade fifty HP for five seconds per selected step, always keeping one HP.
local weapon = {
  definition = {
    copy_from = "stock.double_turn_time",
    name = "Sacrifice",
    panel_icon = "sprites/sacrifice/sacrifice_ico.png",
    handling = {remember_selection=false,ends_turn=false,retreat=-1},
    utility = {effect="scripted"},
    sounds = {"sounds/sacrifice/sacrifice_sound.wav", "sounds/sacrifice/sacrifice_error.wav"},
  },
  requires = {"lib/turn_controls"},
}

function weapon.setup()
  local choice
  require("lib/turn_controls").register("px.sacrifice", {
    choose = function(worm, digit)
      if digit >= 1 and digit <= 5 then
        choice = digit
        wa.sound.play(worm, 106)
      end
    end,
    fire = function(worm)
      if not choice then
        wa.sound.play(worm, "sounds/sacrifice/sacrifice_error.wav")
        return "eat" -- No choice: do not consume ammo or fire the placeholder.
      end
      local requested = choice
      choice = nil
      local steps = math.min(requested, math.floor((worm.hp - 1) / 50))
      if steps < 1 or not worm:reduce_health(50 * steps) then
        wa.sound.play(worm, "sounds/sacrifice/sacrifice_error.wav")
        wa.hud.message_top("Sacrifice: not enough HP", {to="coalition",alliance=worm.alliance})
        return
      end
      wa.world.set_turn_clock(math.min(3600000,wa.world.turn_clock() + 5000 * steps))
      wa.sound.play(worm, "sounds/sacrifice/sacrifice_sound.wav")
      if steps < requested then
        wa.hud.message_top("Sacrifice: added as much time as your HP allows", {to="coalition",alliance=worm.alliance})
      end
    end,
    finish = function() choice = nil end,
    hint = function()
      return choice and string.format("Sacrifice: %d HP for %d seconds, then Space", 50*choice, 5*choice)
        or "Sacrifice: choose 1-5, then Space (50 HP per 5 seconds)"
    end,
  })
end
return weapon
