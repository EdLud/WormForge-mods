# Project X Electric Mine

A WormForge bundle for Project X's Electric Mine
(`PX_pending/weapon_electric_mine.c`).

It holds the weapon and its own modules, so updates to the `px` pack cannot
overwrite them; the effect manager and trail come from the shared `effects.sdk`:

- `weapons/electric_mine.lua` -- WA's mine, with WA's own blast silenced and
  PX's custom electric explosion run in its place.
- `lib/custom_explosion.lua` -- PX's `do_custom_explosion`: damage, push, hole,
  chain arcs and effect, launching the effect itself. Its blast finds worms,
  crates and oil drums through `wa.world.electrical_nearby`; crates and drums
  take the falloff damage through `object:hit`.
- `lib/electric_damage.lua` -- the taze hold: the worm is taken, posed and
  shown `tazed1`/`tazed2` with the loop sound, then released with the push.
- `effects.sdk` (`wf-lib/effects/px_effects`, `wf-lib/effects/trail`) -- PX's
  effect manager (spark, glow, reach bolts), the shared trail, and the spark,
  glow, smoke and beam sheets, ported from `wklua_and_px/utils/px_effects.c`.
- `profiles/Electric Mine.toml` -- just the mine, on the mine slot, infinite
  ammo.
- `test_*.lua` -- the module tests.

## Options

The mine's two numbers are the constants at the top of
`weapons/electric_mine.lua`: `DAMAGE` is the explosion value (its radius and
the falloff's basis) and `PUSH` is the knock, its own stat -- the game default
is twice the damage, raised for a weak blast that still shoves. Both are scaled
by PX's 1.25 and truncated.
