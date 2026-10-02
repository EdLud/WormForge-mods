wa.log("hello from example.hello")

-- Hurt is lockstep: blast / hit / percent / nonlethal / poison both peers already run.
wa.on.hurt(function(hit)
  if hit.phase == "post" and hit.lost > 0 then
    wa.log(hit.kind .. " -" .. tostring(hit.lost) .. " hp")
  end
end)

-- Turn phases arrive in this order. With zero retreat they may share a frame.
wa.on.turn_retreat(function(event)
  wa.log("retreat begins for worm " .. tostring(event.worm.id))
end)
wa.on.turn_end(function(event)
  wa.log("movement ends for worm " .. tostring(event.worm.id))
end)
wa.on.turn_cleanup(function(event)
  wa.log("turn cleaned up for worm " .. tostring(event.worm.id))
end)
