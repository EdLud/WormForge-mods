-- Settings: the options of the Rain and Snow add-ons as the weather reads them, and their defaults for the cycle.
local settings = {}

-- The defaults of each add-on's options, as mod.toml declares them: the cycle's rain or snow when that add-on
-- isn't selected.
settings.DEFAULTS = {
  rain = { rain = 60, wind = 100, clouds = 70, darkness = 25, ripples = true, lightning_chance = 30,
    lightning_effect = "looks", volume = 70 },
  snow = { snow = 60, wind = 100, clouds = 70, settle = false, settle_depth = 10, volume = 50 },
}

function settings.rain(option)
  return {
    amount = option("rain") / 100,
    wind = option("wind") / 100,
    clouds = option("clouds") / 100,
    darkness = option("darkness") / 100,
    ripples = option("ripples"),
    chance = option("lightning_chance"),
    strike = option("lightning_effect") == "strike",
    volume = option("volume") / 100,
  }
end

function settings.snow(option)
  return {
    amount = option("snow") / 100,
    wind = option("wind") / 100,
    clouds = option("clouds") / 100,
    settle = option("settle"),
    settle_depth = option("settle_depth"),
    volume = option("volume") / 100,
  }
end

-- The add-on's defaults, read as `ctx.option` reads its options.
function settings.defaults(kind)
  local values = settings.DEFAULTS[kind]
  return function(key) return values[key] end
end

return settings
