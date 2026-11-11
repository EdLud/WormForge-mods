# Project X Electric Mine

Project X's Electric Mine as a mod of its own; the effect manager and trail
come from the shared `effects.sdk`:

- `weapons/electric_mine.lua` -- the stock mine, its blast silenced and PX's
  electric explosion run in its place.
- `lib/custom_explosion.lua` -- PX's `do_custom_explosion`: damage, push, hole,
  chain arcs and effect, launching the effect itself. The radial damage is
  PX's `Env->Objs` walk through `wa.world.blast`: worms, crates, oil drums,
  mines and Lua actors whose `body.hit_by` takes blasts. It sends the hit as
  the shared `kind = "taze"` (override with `kind`), so a recipient that reads
  kinds sees the electric hit. The taze pass then holds every worm in range.
  A 0 HP worm WA has not started killing is given the same falloff and push by
  hand when the taze is off.
- `lib/electric_damage.lua` -- the taze hold: the worm is taken, posed and
  shown `tazed1`/`tazed2` with the loop sound, then released with the push.
  WA's `dying`/`drowning`/`dead` states stay WA's: no new hold, and a hold that
  starts dying is only let go. A zero-HP worm WA has not started killing is
  still taken, but the hold ends the frame after and hands it back with its
  push; a worm killed during the hold takes no extra damage.
- `lib/taze_mine.lua` -- mark any mine as tazed from an electric weapon. The
  mine keeps WA's stock blast, and the frame it goes draws PX's electric
  explosion (the ring and lens) at the effect radius, then gives the worms in
  PX's electric field the artificial taze (15 release damage, push scaled to
  116/100). The mine carries its trail. Exported as
  `wf-lib/electric/taze_mine`.
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

## Tazing a mine from another electric weapon

`wf-lib/electric/taze_mine` marks any mine. The stock blast stays; the frame the
mine goes, PX's electric explosion is drawn at the effect radius, and worms in the
electric field get the artificial taze: 15 damage on release, the captured blast
push scaled to PX's 116/100, and a trail on the mine. Call it before the mine
can be freed:

```lua
local taze_mine = require("wf-lib/electric/taze_mine")
taze_mine.taze(mine, { owner = actor, damage = damage })
```

`owner` drives the emitter, trail, driver and the explosion effect; `damage`
sets the field radius and the effect radius (default WA's stock mine, 45 →
`(45 * 1.25 + 2) / 2` = 29 px); `effect_radius` overrides the effect alone.
`taze_damage` (default 15), `push`/`push_from` (default 116/100), `push_scale`,
`frames`, `retain` and `radius` are optional. The caller's sprite list needs
`trail.BEAM` and `trail.GLOW`.
