-- Auto Ballista: a turret that shoots arrows at moving enemies.

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
    name = "Auto Ballista",
    panel_icon = "sprites/pyro_turrets/ballista_icon.png",
    is_weapon = true,
    on_fire = function(fire) fires.auto_ballista(fire) end,
  })
end

function weapon.setup()
  local shared = require("lib/shared")
  local pyro = require("lib/pyro_turret")

  local function shoot(t, a, s, shot)
    if not pyro.muzzle_clear(a, shot) then return false end
    local force = pyro.force(s)
    wa.arrows.spawn({ owner = t.owner(a, s), x = shot.x, y = shot.y,
      vx = shot.dx * force, vy = shot.dy * force, damage = 10, gravity_pct = 25 })
    return true
  end

  local function build(kind, id)
    return pyro.new({
      kind = kind, weapon = id, frames = pyro.FRAMES.ballista,
      ammo = 8, tower_len = 16, g_factor = 0.25,
      aim_time = function(dist) return dist / 10 + 1 end, -- "500 pixels per sec"
      hit_by = { worms = true, missiles = true, mines = true, actors = true, bullets = true,
        melee = true, fire = true, dragon_ball = true, blasts = true },
      passage_hit_by = { melee = true, fire = true, dragon_ball = true, blasts = true },
      shoot = shoot,
    })
  end

  local t = build("auto_ballista", "px.auto_ballista")
  shared.fires.auto_ballista = function(fire_ev) t.place(fire_ev) end
  shared.auto_ballista = t
  shared.hazard_turrets["px.auto_ballista"] = function() return build("hazard_auto_ballista") end
end

function weapon.set_options(t, option)
  require("lib/pyro_turret").set_options(t, option)
end

function weapon.configure(ctx)
  weapon.set_options(require("lib/shared").auto_ballista, ctx.option)
end

return weapon
