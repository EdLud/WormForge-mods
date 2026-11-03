-- WormForge's profiler, on this machine. (The FPS counter is public now:
-- Core utilities' "FPS counter" option, wa.hud.fps_counter().)
--
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
-- natives: with profile, the "perf lua:" line also gives the slowest verbs,
--   every call of each summed ("quad", "all"). Off by default: Lua runs
--   slower while it is on.
-- packs, spikes and natives are this add-on's options.
--
-- Presentation only: no timing reaches the game, so it is safe online.
return function(ctx)
  wa.perf.enable({
    profile = true,
    spikes = ctx.option("spikes") == true, packs = ctx.option("packs") == true,
    natives = ctx.option("natives") == true,
  })
end
