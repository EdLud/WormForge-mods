-- Flame Turret: a turret that lobs fire at moving enemies, over the land in their way.

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
    name = "Flame Turret",
    panel_icon = "sprites/pyro_turrets/flame_icon.png",
    is_weapon = true,
    on_fire = function(fire) fires.flame_turret(fire) end,
  })
end

function weapon.setup()
  local shared = require("lib/shared")
  local pyro = require("lib/pyro_turret")
  local turret = require("lib/turret")
  local FLAME_SOUND = 22 -- WA's Flamethrower, as PX plays it

  local function shoot(t, a, s, shot)
    if not pyro.muzzle_clear(a, shot) then return false end
    local force = pyro.force(s) * 4 -- PX throws its fire four times as fast
    wa.fire.spawn({ owner = t.owner(a, s), x = shot.x, y = shot.y,
      vx = shot.dx * force, vy = shot.dy * force,
      count = 0, duration = 1500, up_power = 1, damage = -1, damage_scale = 5 })
    turret.play(a, FLAME_SOUND)
    return true
  end

  local function build(kind, id)
    return pyro.new({
      kind = kind, weapon = id, frames = pyro.FRAMES.flame,
      tazer = "empty", -- a CCustomTurret: the Tazer's arc empties its ammo
      ammo = 18, tower_offset = 19, explode_damage = 45,
      ammo_sprite = pyro.AMMO_FLAME, ammo_size = 40, -- WA's petrol3, PX's sprNum 126
      shoot = shoot,
    })
  end

  local t = build("flame_turret", "px.flame_turret")
  shared.fires.flame_turret = function(fire_ev) t.place(fire_ev) end
  shared.flame_turret = t
  shared.hazard_turrets["px.flame_turret"] = function() return build("hazard_flame_turret") end
end

function weapon.set_options(t, option)
  require("lib/pyro_turret").set_options(t, option)
end

function weapon.configure(ctx)
  weapon.set_options(require("lib/shared").flame_turret, ctx.option)
end

return weapon
