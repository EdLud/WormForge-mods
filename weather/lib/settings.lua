-- Settings: the Weather add-on's options as the rain, the snow and the cycle read them.
local settings = {}

local CLOUDS = 0.7 -- how opaque the band of clouds at the top of the level is
local WIND = 1 -- how much the wind slants the rain and drives the flakes and clouds, as a factor
local DARKNESS = 0.5 -- how much the storm darkens the world in rain
local RAIN_VOLUME = 0.7 -- the rain sound at its heaviest
local SNOW_VOLUME = 0.5 -- the blizzard sound

function settings.rain(option)
  local low, high = option("rain_low"), option("rain_high")
  return {
    amount = math.max(low, high) / 100,
    amount_low = math.min(low, high) / 100,
    every = option("rain_every"),
    wind = WIND,
    clouds = CLOUDS,
    darkness = DARKNESS,
    chance = option("lightning_chance"),
    volume = RAIN_VOLUME,
  }
end

function settings.snow(option)
  return {
    amount = option("snow") / 100,
    wind = WIND,
    clouds = CLOUDS,
    settle_depth = option("settle_depth"),
    volume = SNOW_VOLUME,
  }
end

function settings.cycle(option)
  return {
    clear = option("clear_share"),
    rain = option("rain_share"),
    snow = option("snow_share"),
    melt = option("melt"),
  }
end

return settings
