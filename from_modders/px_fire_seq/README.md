# `wf-lib/fire_seq` — a burst of shots from one `on_fire`

`lib/fire_seq.lua` fires a weapon's burst: the first shot immediately, the rest
from a hidden timer actor `delay` frames apart, while the timer's brain holds
WA's `shots_fired`/`shots_to_fire` so the worm stays in its firing state (its
animation and a `keep_while_firing` hold) for the whole burst.

## Using it from another bundle

```toml
# that bundle's mod.toml
dependencies = ["px.fire_seq"]
```

```lua
local seq = require("wf-lib/fire_seq")
```

Inside this bundle the same module is `require("lib/fire_seq")`. Each consumer
gets its own instance (the engine keeps imports private per pack), so
`seq.cancel(owner)` only stops a burst started by that same pack.

## The two helpers

```lua
seq.fire_sequential_actor({ ... })  -- Lua actors: spawn spec + the keys below
seq.fire_seq_mis({ ... })           -- real WA missiles via wa.weapons.launch
```

| key | meaning |
|---|---|
| `owner` | the firing worm (required) |
| `count` | **total** shots, `12` means twelve |
| `delay` | frames between shots; a number or `function(i, worm)`, default 1 |
| `vx`, `vy` | launch velocity; a number or `function(i, worm)`, read again for every shot so the aim stays live |
| `x`, `y` | spawn point; same forms, defaults to the worm's position |
| `standoff` | push each spawn point this many px along its own velocity, so a missile does not start inside the firing worm |
| `spread` | `{ x = n, y = n }`, up to ±n px/frame, drawn with `wa.random` over thousandths |
| `on_shot(i, worm)` | runs before every shot |
| `on_done(owner, fired)` | runs when the burst ends (last shot, cancel or interruption); `fired` counts a shot launched in the same tick as a cancel |
| `cancel_weapon` | weapon id the worm must still hold; leaving it ends the burst |

`fire_seq_mis` also needs `weapon`, the missile record's id.

Both return the timer actor, and both return `nil` when a burst is already
running for that worm or the worm is dead.

## Stopping a burst

`seq.cancel(owner)` ends WA's counters immediately, so WA leaves its fire method
instead of re-entering with a weapon an impact may have cleared. The timer
settles `on_done` on its next tick, outside WA's fire call. It returns false
when there is no burst, or none left to settle (the drain after the last shot);
a new burst may start as soon as it lets go.

Use `cancel`, not the timer's `despawn`, which stops the shots but leaves the
counters held.

## Behaviour to rely on

- A burst ends early — counters ended, guard released — if the worm dies, loses
  the turn, drops `cancel_weapon`, or leaves the firing states (a blast, a push,
  a teleport). It is never left holding the counters.
- The counters are written only by the timer's brain, never from `on_fire`:
  `on_fire` for a projectile runs inside WA's `CreateWeaponProjectile` hook, and
  grounding WA's fire loop from there changes its state mid-iteration.
- Do not re-enter `wa.weapons.fire` from `on_fire`: the slot's `on_fire` already
  ran this frame, so the shot double-fires.
- After the last shot the guard drains 10 frames, swallowing WA's queued
  re-fire instead of starting a second burst.

## When not to use it

A burst whose shots are the record's own projectile at a fixed interval needs
none of this: keep the record a gun and let WA fire it.

- `gun.burst_size` is how many shots WA fires, and `gun.shot_interval_ms` the
  gap between them.
- WA holds the firing pose, counts its own ammo and drops the loop when the worm
  is interrupted, so the counter hold, the drain and the state checks above have
  nothing to do.
- Every spawn still passes `CreateWeaponProjectile` and reaches the pack's
  `on_fire`, so Lua answers only "what does one shot fly like".

Reference: `Mods/wf-lib/mole_shopper/weapons/precipitator.lua` — a Minigun copy
with `gun = { bullets = 25 }` and an `on_fire` that launches one payload.

Keep this base when the shots are not the record's projectile (Lua actors), the
cadence is not uniform, or the burst must stop on a button release or an impact.

## This bundle's weapons

- `px.ripper_star` — fifteen missiles, `fire_seq_mis`, four frames apart.
- `px.megashark`, `px.megashark_hold` — twelve missiles, four frames apart; the
  hold version fires while Space is held and ends on release.
- `px.famas` — missiles in 3/3/3/2 groups.

`lib/targetting_missiles.lua` is their shared homing pass (one target scan per
frame). It is not exported.

## Checking

`wfcheck --strict <bundle>` and the workspace's `check_paths.py`.
