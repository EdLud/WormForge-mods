-- Mine Reveal: click a mine to give it a fuse of up to three seconds, shown over it until the turn ends.

local weapon = {}

local ID = "px.mine_reveal"
local BEEP = "sounds/mine_reveal/beep.wav"
local REACH = 10 -- pixels from the click, either way
local LONGEST = 2999 -- ms
local HOLD = 40 -- frames the new fuse is held, counting or not
local HOP = -1.1 -- pixels/frame

local revealed = {} -- this turn's: { mine, fuse, hold }
local used = false -- the first use in a match costs nothing

local function reveal(ev)
  local worm = ev.worm
  for _, mine in ipairs(wa.mines.all({ near = { ev.x, ev.y, REACH * 2 } })) do
    if math.abs(mine.x - ev.x) <= REACH and math.abs(mine.y - ev.y) <= REACH then
      local fuse = wa.random(0, LONGEST)
      mine.fuse = fuse
      mine:impulse(0, HOP)
      revealed[#revealed + 1] = { mine = mine, fuse = fuse, hold = HOLD }
      if used then wa.sound.play(worm, BEEP) else worm:ammo(ID, 1) end
      used = true
      return
    end
  end
  wa.sound.play(worm, 120)
  worm:ammo(ID, 1)
  require("lib/weapon_hint").notice(worm, "Nothing found!")
end

weapon.definition = {
  wep = "weps/nuclear_test.wep",
  available_in_caves = true, -- the Nuclear Test record it copies isn't
  name = "Mine Reveal",
  panel_icon = "sprites/mine_reveal/mine_reveal_ico.png",
  sounds = { BEEP },
  on_select = { cursor = true },
  on_click = reveal,
}

function weapon.setup()
  local label = require("lib/sentry_health")
  label.install()
  revealed, used = {}, false
  local last_frame
  wa.on.worm_message(function()
    local frame = wa.world.frame()
    if frame == last_frame or not revealed[1] then return end
    last_frame = frame
    for _, r in ipairs(revealed) do
      if r.hold > 0 and r.mine.alive then
        r.mine.fuse = r.fuse
        r.hold = r.hold - 1
      end
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })
  wa.on.turn_end(function() revealed = {} end)
  wa.on.draw(function()
    for _, r in ipairs(revealed) do
      local mine = r.mine
      if mine.alive then
        local fuse = mine.fuse
        local text = fuse == 0 and "Dud" or string.format("%.1f", math.max(0, fuse) / 1000)
        label.text(text, mine.x, mine.y - 12, 0xFFE8E8E8, wa.depth.OBJECTS - 2)
      end
    end
  end)
end

return weapon
