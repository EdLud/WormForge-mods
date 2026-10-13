-- An add-on with a rule of its own: the worm whose turn starts heals 10 HP.
return function()
  wa.on.turn_start(function(ev)
    ev.worm:heal(10)
  end)
end
