-- Petrol Turret: a turret that lobs Petrol Bombs at moving enemies, over the land in their way.

local weapon = {}

weapon.record = {}

function weapon.definition()
  local fires = require("lib/shared").fires
  local hold = require("lib/prod_hold")
  return require("lib/weapon").merge(weapon.record, {
    -- WA's Mine record, so the worm drops it from a vehicle too; the Prod's hold kept
    copy_from = "stock.mine",
    worm_sprites = hold.worm_sprites,
    params = hold.params,
    name = "Petrol Turret",
    panel_icon = "sprites/pyro_turrets/petrol_icon.png",
    is_weapon = true,
    on_fire = function(fire) fires.petrol_turret(fire) end,
  })
end

function weapon.setup()
  local shared = require("lib/shared")
  local pyro = require("lib/pyro_turret")
  local NEUTRAL = require("lib/turret").NEUTRAL
  local DAMAGE = 15 -- PX's admg: the bomb's launch.explosion.damage
  local LAUNCH_SOUND = 44 -- WA's sound PX plays with each

  local function shoot(t, a, s, shot)
    if not pyro.muzzle_clear(a, shot) then return false end
    local force = pyro.force(s)
    local owner = t.owner(a, s)
    if owner == a and s.alliance ~= NEUTRAL then return false end
    wa.sound.play(a, LAUNCH_SOUND)
    wa.weapons.launch({ weapon = "stock.petrol_bomb", owner = owner,
      x = shot.x, y = shot.y, vx = shot.dx * force, vy = shot.dy * force,
      missile = { explosion = { power = DAMAGE } } })
    return true
  end

  local function build(kind, id)
    return pyro.new({
      kind = kind, weapon = id, frames = pyro.FRAMES.petrol,
      tazer = "empty", -- a CCustomTurret: the Tazer's arc empties its ammo
      ammo = 6, tower_offset = 20,
      ammo_sprite = pyro.AMMO_PETROL, ammo_size = 60, -- WA's petrolbm, PX's sprNum 55
      shoot = shoot,
    })
  end

  local t = build("petrol_turret", "px.petrol_turret")
  shared.fires.petrol_turret = function(fire_ev) t.place(fire_ev) end
  shared.petrol_turret = t
  shared.hazard_turrets["px.petrol_turret"] = function() return build("hazard_petrol_turret") end
end

function weapon.set_options(t, option)
  require("lib/pyro_turret").set_options(t, option)
end

function weapon.configure(ctx)
  weapon.set_options(require("lib/shared").petrol_turret, ctx.option)
end

return weapon
