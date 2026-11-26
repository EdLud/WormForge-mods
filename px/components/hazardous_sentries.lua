-- Hazardous Sentries: neutral sentries and turrets placed on the map at the start of each round.

local KINDS = { -- each option's prefix and its turret's weapon, in the order they're placed
  { key = "sentry_gun", id = "px.sentry_gun" },
  { key = "sentry_laser", id = "px.sentry_laser" },
  { key = "petrol_turret", id = "px.petrol_turret" },
  { key = "flame_turret", id = "px.flame_turret" },
  { key = "mine_turret", id = "px.mine_turret" },
  { key = "auto_ballista", id = "px.auto_ballista" },
}

return {
  install = function(ctx)
    local loader = require("components/loader")
    local index = require("weapons/index")
    local wanted = {}
    for _, kind in ipairs(KINDS) do
      if ctx.option(kind.key) > 0 then
        wanted[#wanted + 1] = kind
        loader.also(index[kind.id])
      end
    end
    loader.load(loader.place(ctx))
    if #wanted == 0 then return end

    local shared = require("lib/shared")
    local spot = require("lib/hazard_spot")
    local hazards = {}
    for _, kind in ipairs(wanted) do
      local module = require(index[kind.id])
      -- the weapon's art and sounds, which only a placed weapon's claim loads
      local spec = module.definition()
      if not ctx.weapons[kind.id] and (spec.sprites or spec.sounds) then
        wa.assets.load({ sprites = spec.sprites, sounds = spec.sounds,
          gpu_prefix = spec.params and spec.params.gpu_prefix })
      end
      local t = shared.hazard_turrets[kind.id]()
      module.set_options(t, function(key) return ctx.option(kind.key .. "_" .. key) end)
      hazards[#hazards + 1] = { t = t, kind = kind, count = ctx.option(kind.key) }
    end

    local placed = false
    wa.on.turn_start(function()
      if placed then return end
      placed = true
      local ground = spot.ground()
      local taken = {}
      local middle = wa.world.size().w / 2
      for _, h in ipairs(hazards) do
        local made = 0
        while made < h.count do
          local x, y = spot.find(ground, taken)
          if not x then break end
          h.t.spawn_neutral(x, y, x < middle and 1 or -1) -- facing the middle of the map
          made = made + 1
        end
        if made < h.count then
          wa.log(string.format("Hazardous Sentries: room for %d of %d %s", made, h.count, h.kind.key))
        end
      end
    end)
  end,
}
