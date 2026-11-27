-- Mad Heli Race: its rules in a window at the first turn and again on Shift + T.

local RULES = {
  { "Mad Heli Race", color = "purple" },
  { "Big Rope Race maps recommended", color = "cyan" },
  { "One Bullet Time per turn", color = "green" },
  { "Shift to Dash", color = "yellow" },
}

return { install = function() require("lib/rules_window").install(RULES) end }
