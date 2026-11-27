-- Random Trap Crate: a booby-trapped weapon crate appears somewhere on the map.

local crate_spot = require("lib/crate_spot")
local weapon = {}

local ID = "px.random_trap_crate"
local TRAP = { damage = 40, radius = 42 } -- the mine riding the crate

weapon.requires = { "lib/crate_spot" }

local traps = {} -- { crate, mine }

local function place(fire)
  local worm = fire.worm
  local x, y = crate_spot.find()
  local ok, crate = false, nil
  if x then ok, crate = pcall(wa.crates.spawn, { x = x, y = y, kind = "weapon", drop = "teleport" }) end
  if not ok or not crate then
    wa.sound.play(worm, 120)
    worm:ammo(ID, 1)
    require("lib/weapon_hint").notice(worm, "No room for a crate!")
    return
  end
  local mine = wa.mines.spawn({ owner = "none", x = crate.x, y = crate.y, fuse = 0, arm = 0,
    damage = TRAP.damage, radius = TRAP.radius, dud_proof = true })
  mine.visible, mine.gravity = false, 0
  traps[#traps + 1] = { crate = crate, mine = mine }
end

function weapon.definition()
  return {
    wep = "weps/freeze.wep",
    name = "Random Trap Crate",
    panel_icon = "sprites/random_trap_crate/icon.png",
    worm_sprites = {
      weaponlnk = "sprites/weapon_crate/take_out.png", weaponlnku = "sprites/weapon_crate/take_outu.png",
      weaponlnkd = "sprites/weapon_crate/take_outd.png",
      wthrow = "sprites/weapon_crate/put_away.png", wthrowu = "sprites/weapon_crate/put_awayu.png",
      wthrowd = "sprites/weapon_crate/put_awayd.png",
      wdynlnk = "sprites/weapon_crate/take_out.png", wdynlnku = "sprites/weapon_crate/take_outu.png",
      wdynlnkd = "sprites/weapon_crate/take_outd.png",
    },
    params = { worm_sprites_animate = true },
    on_fire = place,
  }
end

function weapon.setup()
  traps = {}
  local last_frame
  wa.on.worm_message(function()
    local frame = wa.world.frame()
    if frame == last_frame or not traps[1] then return end
    last_frame = frame
    local kept = {}
    for _, t in ipairs(traps) do
      if not t.mine.alive then
        wa.hud.message_top("** Booby Trapped **")
      elseif not t.crate.alive then
        t.mine:remove()
      else
        t.mine:warp({ x = t.crate.x, y = t.crate.y, vx = 0, vy = 0 })
        kept[#kept + 1] = t
      end
    end
    traps = kept
  end, { msgs = { wa.msg.FRAME_FINISH } })
end

return weapon
