-- Crate Grabber: click a crate to bring it to the worm.

local weapon = {}
local ID = "px.crate_grabber"
local REACH = 12 -- pixels from the click, either way

local function grab(ev)
  local worm = ev.worm
  for _, crate in ipairs(wa.crates.all({ near = { ev.x, ev.y, REACH * 2 } })) do
    if math.abs(crate.x - ev.x) <= REACH and math.abs(crate.y - ev.y) <= REACH then
      wa.sound.play(worm, 67)
      crate:warp({ x = worm.x, y = worm.y - 10 })
      return
    end
  end
  wa.sound.play(worm, 120)
  worm:ammo(ID, 1)
  require("lib/weapon_hint").notice(worm, "No crate found!")
end

weapon.definition = {
  wep = "weps/nuclear_test.wep",
  available_in_caves = true, -- the Nuclear Test record it copies isn't
  name = "Crate Grabber",
  panel_icon = "sprites/crate_grabber/icon.png",
  on_select = { cursor = true },
  on_click = grab,
}

return weapon
