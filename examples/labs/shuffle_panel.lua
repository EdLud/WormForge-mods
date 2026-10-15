-- Each turn, the weapons the profile placed swap places on the panel at
-- random: wa.panel.layout and wa.panel.set_layout. Only where a weapon shows
-- changes; F-keys and clicks pick from the new order at once.
return function()
  wa.on.turn_start(function()
    local layout = wa.panel.layout()
    -- By id first: a table's order isn't the same on every machine, and the
    -- shuffle must be (wa.random is the game's own, the same everywhere).
    local ids = {}
    for id in pairs(layout) do ids[#ids + 1] = id end
    table.sort(ids)
    local places = {}
    for i, id in ipairs(ids) do places[i] = layout[id] end
    for i = #places, 2, -1 do
      local j = wa.random(i)
      places[i], places[j] = places[j], places[i]
    end
    local moves = {}
    for i, id in ipairs(ids) do moves[id] = places[i] end
    wa.panel.set_layout(moves)
  end)
end
