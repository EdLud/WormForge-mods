-- WormForge's FPS counter and profiler, on this machine.
--
-- counter: one line at the top right: the live frame rate, the average over
--   the last 2 s, and the longest frame in the last 5 s, in ms.
-- profile: every 10 s, a "perf:" line in wkLua.log with each part of a
--   rendered frame: its average and worst ms per frame, its share of the
--   frame, and how often it ran.
--
-- Presentation only: no timing reaches the game, so it is safe online.
wa.perf.enable({ counter = true, profile = true })
