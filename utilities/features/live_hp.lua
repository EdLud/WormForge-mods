-- Live HP, originally by reddaz. Commit WA's pending health display directly;
-- native hit, movement, freeze and death handling retain their own states.

-- `worm:show_health()` (0.9.51 DLLs) shows a health on the label and leaves
-- WA its pending damage; an older DLL has only the commit.
local function can_show(worm)
  local ok, show = pcall(function() return worm.show_health end)
  return ok and show ~= nil
end

wa.on.hurt(function(hit)
  if hit.phase ~= "post" or hit.lost <= 0 then return end
  local worm = hit.worm
  -- Keep the active worm's normal health timing.
  if worm.turn or worm.hp < 0 then return end
  -- A victim brought to 0 shows it, but WA keeps the damage it owes: that is
  -- what makes WA run its damage phase once everything settles, where it
  -- kills the worm. Committed, it stood at 0 until the turn ended.
  if worm.hp == 0 and can_show(worm) then
    worm:show_health()
  else
    worm:commit_health()
  end
end)
