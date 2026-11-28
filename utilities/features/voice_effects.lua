-- Voice effects: worms speak lines from their team's sound bank when
-- something happens in the match. Each effect is a switch.

return function(ctx)
  local on = {}
  if ctx.option("skim_voices") then
    require("features/skim_voices")()
    on[#on + 1] = "skim_voices"
  end
  wa.log("voices " .. (#on > 0 and table.concat(on, " ") or "none"))
end
