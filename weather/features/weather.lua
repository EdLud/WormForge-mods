-- Weather: clear skies, rain and snow, picked by their shares at each turn cycle.
local W = require("lib/weather")
local settings = require("lib/settings")

return function(ctx)
  local cycle = settings.cycle(ctx.option)
  W.cycle(cycle)
  if cycle.rain > 0 then
    W.add("rain", settings.rain(ctx.option))
    require("lib/sim").install(W)
  end
  if cycle.snow > 0 then
    W.add("snow", settings.snow(ctx.option))
    require("lib/settle").install(W)
  end
end
