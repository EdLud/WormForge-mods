-- A scheme with rules: the demo scheme's weapons and crates, and one rule of
-- its own. Its mod.toml entry declares changes_rules = true, so the loader
-- says so in green.
local demo = require("scheme")
return {
  crates = demo.crates,
  weapons = demo.weapons,
  install = function()
    -- The worm whose turn starts heals 10 HP.
    wa.on.turn_start(function(ev)
      ev.worm:heal(10)
    end)
  end,
}
