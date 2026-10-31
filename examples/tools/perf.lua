-- WormForge's FPS counter and profiler, on this machine.
--
-- counter: one line at the top right: the live frame rate, the average over
--   the last 2 s, and the longest frame in the last 5 s, in ms.
-- profile: every 10 s, a "perf:" line in wkLua.log with each part of a
--   rendered frame: its average and worst ms per frame, its share of the
--   frame, and how often it ran. A "perf lua:" line splits the Lua time by
--   call. A Lua call of 5 ms or more gets a "perf spike:" line of its own
--   right away: what it was for, the frame, and Lua's memory around it.
-- packs: with profile, that line also shows each pack's hook handler time.
--   Off by default: timing every handler makes each hook call slower.
-- spikes: with profile, each "perf spike:" line also names the Lua lines and
--   the verbs ("[C] play") the call spent its time on. Off by default: Lua
--   runs slower while it samples.
-- packs and spikes are this add-on's options.
--
-- Presentation only: no timing reaches the game, so it is safe online.
return function(ctx)
  wa.perf.enable({
    counter = true, profile = true,
    spikes = ctx.option("spikes") == true, packs = ctx.option("packs") == true,
  })
end
