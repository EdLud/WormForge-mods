-- Let each zero-HP victim die without waiting for the battlefield. Frame
-- polling also covers falls and direct HP writes. WA owns the death
-- animation, explosion and grave; repeat requests are inert.
--
-- "settled": WA's own death, once the worm's own movement stops (its death
-- permission). "in_flight": WA's death started at once, wherever the worm
-- is, and it flies on while it dies (worm:die, Project X's fast death); a
-- worm WA won't start one for (the Kamikaze's flight) still dies when
-- settled. `true` is "settled", as the switch this was.
return function(mode)
  local in_flight = mode == "in_flight"
  wa.on.worm_message(function(worm)
    if not worm.turn and worm.hp == 0 then
      if not (in_flight and worm:die()) then
        worm:allow_death()
      end
    end
  end, { msgs = { wa.msg.FRAME_FINISH } })
end
