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
  The engine clears WA's static flag for a dying worm, so a 0 HP worm is still
  held and released; a worm killed during the hold takes no extra damage.
- `lib/taze_mine.lua` -- mark any mine as tazed from an electric weapon. The
  mine keeps WA's stock blast; after it is gone the worms in PX's electric
  field get the artificial taze (15 release damage, push scaled to 116/100)
  and the mine carries its trail. Exported as `wf-lib/electric/taze_mine`.
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

`wf-lib/electric/taze_mine` marks any mine. The stock blast stays; once the
mine is gone, worms in the electric field get the artificial taze: 15 damage
on release, the captured blast push scaled to PX's 116/100, and a trail on
the mine. Call it before the mine can be freed:

```lua
local taze_mine = require("wf-lib/electric/taze_mine")
taze_mine.taze(mine, { owner = actor, damage = damage })
```

`owner` drives the emitter, trail and driver; `damage` sets the field radius
(default WA's stock mine, 45); `taze_damage` (default 15), `push`/`push_from`
(default 116/100), `push_scale`, `frames`, `retain` and `radius` are optional.
The caller's sprite list needs `trail.BEAM` and `trail.GLOW`.
