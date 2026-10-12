-- Highlander: what its modules share, one table per match.
-- Split from rules.lua by tools/split_highlander.py.
local shared = {}

-- Where each weapon sits this match. The code names every Highlander weapon
-- by its home slot, the stock slot PX's layout gives it ("bazooka" is the
-- Double Bazooka); as a component it may be placed on any slot, or not at
-- all. shared.slot(home) is the slot it sits on (nil when it isn't placed),
-- shared.home(slot) the weapon on a slot. Until shared.place is called (the
-- pack in one piece, rules.lua) every weapon is at home.
local placed, homes

function shared.place(map)
  placed, homes = map, {}
  for home, slot in pairs(map) do
    homes[slot] = home
  end
end

function shared.slot(home)
  if not placed then return home end
  return placed[home]
end

function shared.home(slot)
  if not placed then return slot end
  return slot and homes[slot]
end

return shared
