-- Settings: the Weather add-on's options as the rain, the snow and the cycle read them.
local settings = {}

local CLOUDS = 0.7 -- how opaque the band of clouds at the top of the level is
local WIND = 1 -- how much the wind slants the rain and drives the flakes and clouds, as a factor
local DARKNESS = 0.5 -- how much the storm darkens the world in rain

function settings.rain(option)
  return {
    amount = option("rain") / 100,
    wind = WIND,
    clouds = CLOUDS,
    darkness = DARKNESS,
    ripples = option("ripples"),
    chance = option("lightning_chance"),
    strike = option("lightning_effect") == "strike",
    volume = option("volume") / 100,
  }
end

function settings.snow(option)
  return {
    amount = option("snow") / 100,
    wind = WIND,
    clouds = CLOUDS,
    settle = option("settle"),
    settle_depth = option("settle_depth"),
    volume = option("snow_volume") / 100,
  }
end

function settings.cycle(option)
  return {
    change_chance = option("change_chance"),
    rain_weight = option("rain_weight"),
    snow_weight = option("snow_weight"),
    clear_weight = option("clear_weight"),
    start = option("start"),
    melt = option("melt"),
  }
end

return settings
