-- Weather: rain or snow all match, or a cycle that turns between rain, snow and clear spells.
local W = require("lib/weather")
local settings = require("lib/settings")

return function(ctx)
  local mode = ctx.option("weather")
  if mode == "cycle" then W.cycle(settings.cycle(ctx.option)) end
  if mode ~= "snow" then
    W.add("rain", settings.rain(ctx.option))
    require("lib/sim").install(W)
  end
  if mode ~= "rain" then
    W.add("snow", settings.snow(ctx.option))
    require("lib/settle").install(W)
  end
end
