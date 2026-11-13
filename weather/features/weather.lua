-- Rain: rain, storm clouds, rings on water and puddles, and lightning.
local W = require("lib/weather")

return function(ctx)
  W.add("rain", require("lib/settings").rain(ctx.option))
  require("lib/sim").install(W)
end
