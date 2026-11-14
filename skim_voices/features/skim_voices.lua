-- Skim Voices: each skim off the water gets a cheer from the team whose turn
-- it is, in the voice of its sound bank. A worm's skims count up through the turn:
-- Amazing, Brilliant, Excellent, then Perfect for the fourth and every skim
-- after it. Every count starts again at the next turn.
local LINES = { "speech/Amazing", "speech/Brilliant", "speech/Excellent", "speech/Perfect" }

return function()
  if not wa.on.skim then
    wa.log("skim voices: this WormForge has no skim event; update it to hear the voices")
    return
  end

  local turn_worm = nil
  local skims = {}

  wa.on.turn_start(function(event)
    turn_worm = event.worm
    skims = {}
  end)

  wa.on.skim(function(event)
    local id = event.worm.id
    local count = (skims[id] or 0) + 1
    skims[id] = count
    -- The turn's worm speaks for its team; before any turn, the skimming worm.
    local speaker = turn_worm or event.worm
    wa.sound.play(speaker, LINES[math.min(count, #LINES)])
  end)
end
