-- Specialists' Barrel Launcher (PX weapon_barrel_launchers: bl_script.txt).
-- Keys 1-5 pick one of five of PX's special oil drums; the launcher fires
-- that drum instead of its shell, at the shell's launch. The drums are
-- lib/oil_drums' own kinds, drawn and bursting as the map's.
local weapon = {}
local ID = "px.barrel_launcher"
local ART = "sprites/barrel_launcher/"
local TAZER = "sounds/barrel_launcher/tazsnd.wav"

-- barreltypebl 0..4: its drum, its message and its sound.
local CHOICES = {
  { kind = "napalm", name = "Napalm Barrel", sound = 59 },
  { kind = "mine", name = "Mines Barrel", sound = 88 },
  { kind = "electric", name = "Electric Barrel", sound = TAZER },
  { kind = "icy", name = "Ice Barrel", sound = 24 },
  { kind = "teleport", name = "Teleport Barrel", sound = 67 },
}

-- The electric drum fires the Electric Grenade's arc.
weapon.requires = { "weapons/electric_grenade" }

local choice = 1 -- reset to the napalm drum at each turn's start and end

local function launch(fire)
  local worm = fire.worm
  -- PX builds the drum where the shell would start; a drum WA had to move
  -- out of the land is taken back, the shot refunded.
  if wa.world.collides({ x = fire.x, y = fire.y, radius = 9 }) then
    wa.sound.play(worm, 120)
    worm:ammo(ID, 1)
    require("lib/weapon_hint").notice(worm, "No space to launch!")
    return
  end
  require("lib/oil_drums").launch(CHOICES[choice].kind, fire.x, fire.y, fire.vx, fire.vy)
end

weapon.definition = {
  -- PX's record from the Specialists scheme: a charged launcher on the Sheep
  -- Launcher's slot; its shell is never fired.
  wep = "weps/barrel_launcher.wep",
  name = "Barrel Launcher",
  panel_icon = ART .. "bl_ico.png",
  worm_sprites = {
    weaponlnk = ART .. "aim.png", weaponlnku = ART .. "aimu.png", weaponlnkd = ART .. "aimd.png",
    wthrow = ART .. "draw.png", wthrowu = ART .. "drawu.png", wthrowd = ART .. "drawd.png",
  },
  sounds = { TAZER },
  on_fire = launch,
}

function weapon.setup()
  local drums = require("lib/oil_drums")
  drums.install({})
  drums.load_assets()
  wa.on.turn_start(function() choice = 1 end)
  wa.on.turn_end(function() choice = 1 end)
  -- The digit's press, per worm: this runs for every worm each frame.
  local held = {}
  wa.on.worm_message(function(worm)
    local digit
    if worm.turn and worm.weapon == ID then digit = wa.world.keys().digit end
    local pressed = digit and digit >= 1 and digit <= #CHOICES and digit or nil
    if pressed and held[worm.id] ~= pressed then
      choice = pressed
      wa.sound.play(worm, CHOICES[pressed].sound)
    end
    held[worm.id] = pressed
  end, { msgs = { wa.msg.FRAME_FINISH } })
  -- After the keys, so a choice shows the frame it is made.
  require("lib/weapon_hint").hint(ID, function()
    return "Barrel Launcher: " .. CHOICES[choice].name .. "\n1-" .. #CHOICES .. ": choose a barrel"
  end)
end

return weapon
