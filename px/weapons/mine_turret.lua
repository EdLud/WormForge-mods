-- Mine Turret: a turret that lobs armed mines at moving enemies, over the land in their way.

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
    name = "Mine Turret",
    panel_icon = "sprites/pyro_turrets/mine_icon.png",
    is_weapon = true,
    on_fire = function(fire) fires.mine_turret(fire) end,
  })
end

function weapon.setup()
  local shared = require("lib/shared")
  local pyro = require("lib/pyro_turret")

  local function shoot(t, a, s, shot)
    if not pyro.muzzle_clear(a, shot) then return false end
    local force = pyro.force(s)
    wa.mines.spawn({ owner = t.owner(a, s), x = shot.x, y = shot.y,
      vx = shot.dx * force, vy = shot.dy * force,
      fuse = 400, arm = 0, damage = 50, radius = 48 })
    return true
  end

  local function build(kind, id)
    return pyro.new({
      kind = kind, weapon = id, frames = pyro.FRAMES.mine,
      ammo = 6, shoot = shoot,
    })
  end

  local t = build("mine_turret", "px.mine_turret")
  shared.fires.mine_turret = function(fire_ev) t.place(fire_ev) end
  shared.mine_turret = t
  shared.hazard_turrets["px.mine_turret"] = function() return build("hazard_mine_turret") end
end

function weapon.set_options(t, option)
  require("lib/pyro_turret").set_options(t, option)
end

function weapon.configure(ctx)
  weapon.set_options(require("lib/shared").mine_turret, ctx.option)
end

return weapon
