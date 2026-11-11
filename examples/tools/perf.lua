-- Profiler: wormForge's profiler (wkLua.log), on this machine.

return function(ctx)
  wa.perf.enable({
    profile = true,
    spikes = ctx.option("spikes") == true, packs = ctx.option("packs") == true,
    natives = ctx.option("natives") == true,
  })
end
