-- Specialists' Mine Launcher (PX weapon_mine_launchers: minelauncher_scr.txt,
-- by StepS, improved by 0rang3). Keys 1-3 pick the mine it fires instead of
-- its shell: instant, sticky or invisible. Each is one of WA's own mines.
local weapon = {}
local ID = "px.mine_launcher"
local ART = "sprites/mine_launcher/"

-- minetype 0..2: PX's message, and the mine (CMineParams: Prefuse is the
-- arming wait, Fuse the fuse once triggered; all 50 damage, radius 48).
local MODES = {
  { name = "Instant Mine, 0 SEC", arm = 400, fuse = 0, keep = 96 },
  { name = "Sticky Mine, 1.5 SEC", arm = 2000, fuse = 1500, sticky = true },
  { name = "Invisible Mine, 3 SEC", arm = 2000, fuse = 3000, keep = 96, hidden = true },
}
-- WA's select-weapon message: PX's M_SETWEAPON resets the choice too.
local SELECT_WEAPON = 51

local mode = 1      -- reset to the instant mine at each turn's start and end
local sticky = {}   -- mine uid -> { mine, stuck, released }: PX's StickyWork

-- CMine::Collide for a sticky mine: the first touch stops it where it is,
-- weightless (sounds 107 and 56); the next lets it fall again.
local function bump(mine, ev)
  local s = sticky[mine.uid]
  if not s or s.released then return end
  if not s.stuck then
    mine.x, mine.y, mine.vx, mine.vy = ev.x, ev.y, 0, 0
    mine.gravity = 0
    wa.sound.play(mine, 107)
    wa.sound.play(mine, 56)
    s.stuck = true
  else
    mine.gravity = 1
    s.released = true
  end
end

local function launch(fire)
  local m = MODES[mode]
  local mine = wa.mines.spawn({
    owner = fire.worm, x = fire.worm.x, y = fire.worm.y, vx = fire.vx, vy = fire.vy,
    arm = m.arm, fuse = m.fuse, damage = 50, radius = 48,
    -- DumpingC 0.96: the speed kept along a surface until WA arms it.
    terrain_keep_speed_pct = m.keep,
    on_bump = m.sticky and bump or nil,
  })
  if not mine then return end
  if m.hidden then mine.visible = false end
  if m.sticky then sticky[mine.uid] = { mine = mine } end
end

weapon.definition = {
  -- PX's record from the Specialists scheme: a charged launcher on the
  -- Mortar's slot; its shell is never fired.
  wep = "weps/mine_launcher.wep",
  name = "Mine Launcher",
  panel_icon = ART .. "minelauncher_ico.png",
  worm_sprites = {
    weaponlnk = ART .. "aim.png", weaponlnku = ART .. "aimu.png", weaponlnkd = ART .. "aimd.png",
    wthrow = ART .. "draw.png", wthrowu = ART .. "drawu.png", wthrowd = ART .. "drawd.png",
  },
  on_fire = launch,
}

function weapon.setup()
  wa.on.turn_start(function() mode = 1 end)
  wa.on.turn_end(function() mode = 1 end)
  local held, last = {}, nil
  wa.on.worm_message(function(worm, msg)
    if msg == SELECT_WEAPON then
      if worm.turn then mode = 1 end
      return
    end
    -- A stuck mine something moved falls again (CMine::Message, once a frame).
    local frame = wa.world.frame()
    if frame ~= last then
      last = frame
      local live = {}
      for _, mine in ipairs(wa.mines.all()) do
        live[mine.uid] = true
        local s = sticky[mine.uid]
        if s and s.stuck and not s.released and (mine.vx ~= 0 or mine.vy ~= 0) then
          mine.gravity = 1
          s.released = true
        end
      end
      for uid in pairs(sticky) do
        if not live[uid] then sticky[uid] = nil end
      end
    end
    -- 1-3 pick the mine, per worm (this runs for every worm each frame).
    local digit
    if worm.turn and worm.weapon == ID then digit = wa.world.keys().digit end
    local pressed = digit and digit >= 1 and digit <= #MODES and digit or nil
    if pressed and held[worm.id] ~= pressed then
      mode = pressed
      wa.sound.play(worm, 92)
    end
    held[worm.id] = pressed
  end, { msgs = { wa.msg.FRAME_FINISH, SELECT_WEAPON } })
  -- After the keys, so a choice shows the frame it is made.
  require("lib/weapon_hint").hint(ID, function()
    return "Mine Launcher: " .. MODES[mode].name .. "\n1-" .. #MODES .. ": choose a mine"
  end)
end

return weapon
