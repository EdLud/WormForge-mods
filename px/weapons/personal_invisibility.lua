-- Personal Invisibility: invisibility for one worm, for three turns or until it attacks.

local weapon = {}
local ID = "px.personal_invisibility"
local DING = "sounds/personal_invisibility/ding.wav"
local TURNS = 4

weapon.definition = {
  copy_from = "stock.double_turn_time",
  name = "Personal Invisibility",
  panel_icon = "sprites/personal_invisibility/ico_pinvisibility.png",
  handling = { remember_selection = false, ends_turn = false, retreat = -1 },
  utility = { effect = "scripted" },
  sounds = { DING },
}
weapon.defaults = { instant_use = "auto_use" }
weapon.requires = { "lib/turn_controls" }

function weapon.setup()
  local left = {}
  local last_turn
  local function fire(worm)
    worm.invisibility = not worm.invisibility
    if worm.invisibility then
      require("lib/weapon_hint").notice(worm, "Invisible for " .. (TURNS - 1) .. " turns")
    end
    wa.sound.play(worm, DING)
  end
  require("lib/turn_controls").register(ID, {
    fire = fire,
    on = function(worm)
      if worm.invisibility then return false end
      fire(worm)
      return true
    end,
  })
  wa.on.worm_message(function()
    local frame = wa.world.frame()
    if frame == last_turn then return end
    last_turn = frame
    for _, w in ipairs(wa.worms.all()) do
      if w.invisibility then
        left[w.id] = (left[w.id] or TURNS) - 1
        if left[w.id] <= 0 then
          left[w.id] = TURNS
          w.invisibility = false
          wa.sound.play(w, DING)
        end
      end
    end
  end, { msgs = { wa.msg.TURN_STARTED } })
end

function weapon.configure(ctx)
  require("lib/turn_controls").configure(ID, ctx.data)
end

return weapon
