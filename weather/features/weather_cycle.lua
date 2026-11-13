-- Weather cycle: at the start of each turn cycle the weather may turn to rain, snow or a clear spell.
local W = require("lib/weather")

return function(ctx)
  W.cycle({
    change_chance = ctx.option("change_chance"),
    rain_weight = ctx.option("rain_weight"),
    snow_weight = ctx.option("snow_weight"),
    clear_weight = ctx.option("clear_weight"),
    start = ctx.option("start"),
    melt = ctx.option("melt"),
  })
end
