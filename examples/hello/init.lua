wa.log("hello from example.hello")

-- Hurt is lockstep: blast / hit / percent / nonlethal / poison both peers already run.
wa.on.hurt(function(hit)
  if hit.phase == "post" and hit.lost > 0 then
    wa.log(hit.kind .. " -" .. tostring(hit.lost) .. " hp")
  end
end)
