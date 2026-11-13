-- Snow: flakes drifting down behind the land under white clouds, settling on open ground if asked.
local W = require("lib/weather")

return function(ctx)
  W.add("snow", require("lib/settings").snow(ctx.option))
  require("lib/settle").install(W)
end
