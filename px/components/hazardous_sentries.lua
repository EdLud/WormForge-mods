-- Hazardous Sentries: neutral sentries and turrets placed on the map at the start of each round.

-- Each kind's share option, its turret's weapon and its fixed settings.
-- The settings are the add-on's own: the weapons' options don't reach these copies.
local PYRO = { health = 50, fire_rate = 400, fire_increase_pct = 12 }
local function pyro(ammo)
  local settings = { ammo = ammo }
  for k, v in pairs(PYRO) do settings[k] = v end
  return settings
end
local KINDS = {
  { key = "sentry_gun_share", name = "Sentry Gun", id = "px.sentry_gun", settings = { health = 50, ammo = 20, damage = 2, push_pct = 100 } },
  { key = "sentry_laser_share", name = "Sentry Laser", id = "px.sentry_laser", settings = { health = 35 } },
  { key = "petrol_turret_share", name = "Petrol Turret", id = "px.petrol_turret", settings = pyro(3) },
  { key = "flame_turret_share", name = "Flame Turret", id = "px.flame_turret", settings = pyro(6) },
  { key = "mine_turret_share", name = "Mine Turret", id = "px.mine_turret", settings = pyro(3) },
  { key = "auto_ballista_share", name = "Auto Ballista", id = "px.auto_ballista", settings = pyro(3) },
}

local SHARED_OPTIONS = { tracking_pct = true, aim_ahead = true } -- one setting for every kind

-- The kind of the next hazard, by the shares: drawn only when more than one has a share.
local function next_hazard(hazards, total)
  if #hazards == 1 then return hazards[1] end
  local r = wa.random(1, total)
  for _, h in ipairs(hazards) do
    if r <= h.upto then return h end
  end
end

return {
  install = function(ctx)
    local loader = require("components/loader")
    local index = require("weapons/index")
    local density = ctx.option("density")
    local wanted = {}
    for _, kind in ipairs(KINDS) do
      if density > 0 and ctx.option(kind.key) > 0 then
        wanted[#wanted + 1] = kind
        loader.also(index[kind.id])
      end
    end
    loader.load(loader.place(ctx))
    if #wanted == 0 then return end

    local shared = require("lib/shared")
    local spot = require("lib/hazard_spot")
    local hazards, total = {}, 0
    for _, kind in ipairs(wanted) do
      local module = require(index[kind.id])
      -- the weapon's art and sounds, which only a placed weapon's claim loads
      local spec = module.definition()
      if not ctx.weapons[kind.id] and (spec.sprites or spec.sounds) then
        wa.assets.load({ sprites = spec.sprites, sounds = spec.sounds,
          gpu_prefix = spec.params and spec.params.gpu_prefix })
      end
      local t = shared.hazard_turrets[kind.id]()
      module.set_options(t, function(key)
        if SHARED_OPTIONS[key] then return ctx.option(key) end
        local value = kind.settings[key]
        if value == nil then error("Hazardous Sentries: no " .. kind.name .. " setting " .. key) end
        return value
      end)
      total = total + ctx.option(kind.key)
      hazards[#hazards + 1] = { t = t, kind = kind, upto = total }
    end

    local placed = false
    wa.on.turn_start(function()
      if placed then return end
      placed = true
      local ground = spot.ground()
      local count = spot.count(density)
      local taken = {}
      local middle = wa.world.size().w / 2
      local made = 0
      while made < count do
        local h = next_hazard(hazards, total)
        local x, y = spot.find(ground, taken)
        if not x then break end
        h.t.spawn_neutral(x, y, x < middle and 1 or -1) -- facing the middle of the map
        made = made + 1
      end
      if made < count then
        wa.log(string.format("Hazardous Sentries: room for %d of %d", made, count))
      end
    end)
  end,
}
