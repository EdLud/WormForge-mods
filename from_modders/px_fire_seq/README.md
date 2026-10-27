# Project X Sequential Fire (`px.fire_seq`)

Four of Project X's guns and the base that fires their bursts, on WormForge
API 4.

| Component | Panel default | What it is |
|---|---|---|
| `px.ripper_star` | F10 col 1 | **Ripper Star** -- fifteen shurikens in one burst, each on the ninja star's grey ribbon, 4 damage and a shove to anything within 20 px of where one lands, or a star left in the land. |
| `px.megashark` | F10 col 2 | **Megashark** -- twelve chlorophyte bullets in one burst, each on a long green trail, four to a target, homing past 90 px and blasting with the record's own 9-power, 670-push explosion. |
| `px.megashark_hold` | F10 col 3 | **Megashark (hold to fire)** -- the same bullets on its own slot, firing the inventory's ammo (20 at most) while Space is held; releasing Space ends the burst after the shot already in flight. |
| `px.famas` | F3 col 6 | **FAMAS** -- three-round bursts, three bursts, then two on the last; each round is a straight 13-damage bullet with a 250 push and a 5000 ms fuse. |

Profiles for one weapon each are in `profiles/`; load them from the mod
loader's Profile tab, or copy them into `WormForge/Profiles/` by hand.

## The base: `lib/fire_seq.lua`

PX sequences a weapon by overriding `CWorm::FireFinal` and **returning before
the stock fire** so WA loops the shot itself:

* Ripper Star (`ripper_fire.txt:11-32`): fifteen shots while `RSShotsFired<=14`.
* Megashark (`megashark_firing.txt:49-76`): twelve while `MShotsFired<=11`.
* FAMAS (`fam_script.txt:56-102`): three per pull, three pulls, then two.

Both also hold `nShoots = 1; nShooted = 0;` every frame (`ripper_fire.txt:42-47`,
`megashark_firing.txt:123-128`) so WA keeps firing with the aim live.

API 4 has no global shot hook and no way to run `FireFinal` again, but it
*does* expose PX's two counters as `worm.shots_to_fire` and
`worm.shots_fired`. So the base does the burst with a timer and holds the
counters for the animation:

```lua
local seq = require("lib/fire_seq")

seq.fire_sequential_actor({ ... })  -- actors (spawn spec + count/delay/spread)
seq.fire_seq_mis({ ... })           -- real WA missiles via wa.weapons.launch
```

* The first shot fires immediately; a hidden, bodiless actor fires the rest,
  one every `delay` frames, so the cadence is the pack's, not WA's delay.
* While the burst runs the timer's brain **holds `shots_fired = 0,
  shots_to_fire = 1`** every frame, so WA keeps the worm in its firing state:
  its firing animation, and a `keep_while_firing` hold, run through the whole
  burst. The held counters also make WA fire the slot again each delay; that
  re-fire reaches the caller's `on_fire` again, where the base swallows it,
  exactly as the laser's guard does (`laser_gun.lua:155`). After the last shot
  the counters are ended (`shots_fired = shots_to_fire`, `laser_gun.lua:147`)
  and the guard drains ten frames, so a queued re-entry is swallowed rather
  than starting a second burst.
* The counters are written **only from the timer's brain**, never from
  `on_fire` -- the laser's own shape (`laser_gun.lua:180`). For a projectile
  `on_fire` runs inside WA's `CreateWeaponProjectile` hook, so grounding WA's
  fire loop from there changes its state inside its own iteration; that was the
  1.0.1 crash.
* The burst also ends early -- counters ended, guard released -- if the worm is
  dead, is not the turn's worm, no longer holds `cancel_weapon`, or is in a
  state it does not fire in: the laser's own stop line (`laser_gun.lua:176`)
  with the state list keyed by raw `state_id` rather than `worm.state` labels,
  which are missing for walking and the hit/blast states. A blast, a push or a
  teleport that interrupts the firing stops the burst instead of being fired
  into, and never leaves the counters held.
* `standoff = n` pushes every shot's spawn point `n` px along its own velocity
  after the offsets are resolved, so a projectile does not start inside the
  firing worm and burst on it at once (the laser's 24 px, `laser_gun.lua:53`).
* `count` is the **total** shots (12 means twelve).
* `x`, `y`, `vx`, `vy` are a number or a `function(i, worm)` called again for
  every shot, so the aim stays live.
* `spread = { x = n, y = n }` adds up to ±n px/frame, drawn with `wa.random`
  over integer thousandths (PX's `RandomFloat(-0.7,0.7)` is `spread = { y = 0.7 }`).
* `on_shot(i, worm)` runs before every shot.
* `on_done(owner, fired)` runs when the burst ends -- after the last shot, on a
  cancel, or on an interruption -- with `fired` the number of shots that left,
  including one launched in the same tick as a cancel. The hold-to-fire
  Megashark uses it for its absolute ammo write.
* `cancel_weapon = "<id>"` is the weapon the worm must still hold (`px.ripper_star`,
  `px.megashark`, `px.megashark_hold`); it ends the burst if the player's
  selection leaves it.
* `seq.cancel(owner)` stops the burst running for that worm: it ends the
  counters now, so WA leaves its fire method instead of re-entering with a
  weapon an impact may have cleared, then the timer settles the burst
  (`on_done`) on its next tick, outside WA's fire call. It returns false when
  there is no burst, or none left to settle (the drain after the last shot); a
  new burst may start as soon as it lets go.
* Both return the timer actor; use `cancel` rather than despawning it, which
  stops the shots but leaves the counters held.

The rejected alternatives are recorded in the file's header: re-entering
`wa.weapons.fire`, where the slot's `on_fire` already ran this frame, so it
double-fires; and holding the counters from `on_fire`, which for a projectile
runs inside WA's `CreateWeaponProjectile` hook and crashed the match (1.0.1).
Only the timer's brain touches them, as the laser's does.

## The land trace

`wa.land.trace` is a Bresenham line (`crates/engine/src/world.rs:1960`); it can
skip a 1 px diagonal wall at a pixel corner. The Megashark, its hold version
and the FAMAS explode at its hit point. A Lua supercover over `wa.land.solid`
was tried and also showed gaps in game, so it was removed. The engine issue is
#3.

## The weapons

### Ripper Star (`weapons/ripper_star.lua`)

> Live build: the missile path (`seq.fire_seq_mis` + `on_explode`).
> The actor description below is `weapons/ripper_star3.lua`, kept for reference.

* Record: PX's own (`weps/ripper_star_wep.wep`, type 1 / method 3). Its blast
  is 0, so the damage is the port's. The record's missile never flies.
* Burst: `fire_sequential_actor`, fifteen Lua star actors four frames apart --
  WA's own fire cycle for the record, which is the cadence PX's `FireFinal`
  loop gets for free -- launched from the worm's live position with PX's
  offsets (3.4 px up; below aim 0.165, 3.1 px more and 2 px forward).
* Velocity: PX's own (`ripper_fire.txt:20-21`), from the worm's **live aim at
  each shot** (PX's `FireAngle`, rebuilt by `FireFinal` every loop and moved by
  the up/down keys through the burst, `:86-99`) with PX's small wobble
  (`:96-98`).
* Flight: the actor moves at 27 px/frame (PX's 45 is too fast for the actor's
  terrain sweep, which can skip a thin wall) and adds a chosen 0.35 px/frame²
  gravity, the Megashark's value; the record's 100% has no API 4 unit and made
  the stars dive. It sets the 32-orientation sheet's frame from the velocity
  every frame and sweeps the step against worms, mines, crates and the land.
  The first tick also traces the 12 px standoff from the muzzle, so a wall
  inside that gap is bitten at its surface rather than 12 px in; a star that
  never lands is dropped after 300 frames.
* Impact: the first worm, mine, barrel or crate within a strict 20 px square
  takes 4 damage and a quarter of the star's speed (through WA's own hit,
  `worm:hurt{ vx, vy }`), or a crate/barrel the same damage and half the
  speed; failing that, the turn's worm within 25 px; failing both, the star is
  stamped into the land in one of 32 orientations, with `rippers_impact.wav`.
  The stamp is pulled back along the incoming velocity by the cell's 5 px
  centre-to-tip, so the needle's point meets the surface instead of its middle.
  A hit on the firing worm is queued and paid from its own `FRAME_FINISH`, with
  `seq.cancel` first, so no hit lands while WA still has a shot pending.
* Offset: PX's muzzle offsets (the forward part re-applied with the worm's
  current facing each shot, so a mid-burst flip mirrors it), plus
  `standoff = 12` px along the launch direction, so a star does not spawn
  inside the firing worm and bite the owner on its first brain tick.
* Art: the ninja star's 32-orientation sheet (the request: "Ripper Star
  launches the shurikens we just did"); the hold is PX's Ripper gun (frame 7 of
  `PX_pending/weapgunssheet.png`) with PX's own hold numbers, drawn by the
  engine's `spec.hold` while aiming (including its pick grow-in) and by
  `lib/px_hold_art.lua` only on the two firing frames (see "The gun art"). The
  record's own particle trail is cleared (0x68 was 457), as the ninja star's
  record now is, and every star flies on the same grey ribbon as the ninja star
  (`effects_sdk/libs/trail.lua`: 7 points, one a frame, half the module's width; at
  27 px/frame it is ~3x the thrown star's length, so `max` is the dial).

### Megashark (`weapons/megashark.lua`)

* Record: PX's own (`weps/megashark_wep.wep`, type 1 / method 3).
* Burst: `fire_sequential_actor`, twelve bullets four frames apart (WA's own
  fire cycle for the record, the cadence PX's `FireFinal` loop gets for free),
  each an invisible-to-WA Lua actor with WA's missile shape.
* Homing (`megashark_home.txt`): arms 90 px from the firing worm; every 2
  frames picks the closest **visible** enemy (a terrain trace), skipping
  targets already carrying four bullets, and steers its velocity toward
  `direction * 15.5` by 0.53.
* Impact: the record's two explosion numbers, each where it belongs: `power`
  9 (`+0x54`, the damage and the radius) becomes `damage`, and `push_pct` 670
  (`+0x50`, the knockback) becomes `id` -- the mapping `a:explode` uses
  (`crates/engine/src/actor.rs:2762-2786`; `px_hold/lib/px_blast_zone.lua:135-146`).
  A bullet knocks a worm hard and digs a small crater.
* Terrain: `wa.land.trace` runs from the previous -> next step and the bullet
  explodes at the hit point. A 1 px diagonal wall can still be skipped (issue
  #3). Worms, mines, crates and barrels use a segment check over the same step.
* Trail: the clorophyte bullet's long green streak is an addition (PX's record
  has no trail sprite, `+0x68` = 0): `effects_sdk/libs/trail.lua` sampled from each
  bullet's own brain (`trail.sample`), 26 points one a frame (~400 px), 5 px
  core and 10 px glow. The brain also samples on the frame a bullet arms (it
  returns before moving that frame); skipping it ended the trail at ~90 px,
  because the driver's clock ticks on that same frame -- the "green for a split
  second" bug. `effects_sdk/libs/trail.lua`'s `STALE` is 3 for the same reason.
* Worm: the record's hold pose (`+0x34`) is 0, which WA answers with sprite 0
  in a fire state; the engine maps that 0 to a worm sheet only while aiming
  (`crates/engine/src/worm_sprite.rs:374-376`), so the worm vanished on every
  0x6A/0x6B frame. `fires = { subtype = 4 }` names the minigun pose (the
  Ripper's), whose `wminif` 573-575 the claim maps to `weaponfire*` and so to
  the PX aim sheet.
* Offset: PX's muzzle offsets (including the low-angle 2 px forward nudge, and
  the forward part re-applied with the worm's current facing each shot, so a
  mid-burst flip mirrors it), plus `standoff = 12` px along the launch
  direction, so a bullet does not start inside the firing worm (or the land
  under it) and explode on the owner at once.
* Art: PX's Megashark gun (frame 1 of `weapgunssheet.png`) with PX's hold
  numbers, drawn by the engine's `spec.hold` while aiming (including its pick
  grow-in) and by `lib/px_hold_art.lua` only on the two firing frames (see
  "The gun art"). The bullet PNG is a **stand-in**: PX draws from `redWeapSheet`
  subsprite 4 / `clorophyte.png`, neither of which is in the repo.

### Megashark, hold to fire (`weapons/fire_while_holding_megashark.lua`)

A copy of the Megashark on its own component and panel slot
(`px.megashark_hold`), so both versions can be selected together. Flight,
homing, art and the record's blast are unchanged. Two things differ:

* The burst is `worm:ammo(ctx.id)` at the moment the trigger is pulled:
  finite ammo fires that many bullets, infinite fires `MAX_BURST = 20`.
  `on_done(owner, fired)` writes `start - fired` back with an absolute
  `worm:ammo(id, { set = n })`, as Highlander does. That settles a burst that
  ended by the last shot, a release, a blast, a death, a turn end or a weapon
  swap, including a shot that left in the same tick as a cancel. Infinite ammo
  is never written.
* A `FRAME_FINISH` handler reads `wa.world.keys().space`. While Space is held
  the timer keeps firing; on the first frame it is not held the handler calls
  `seq.cancel(owner)`. The shot already in flight still leaves, and the timer's
  next tick settles `on_done` outside WA's fire call. The weapon is therefore
  used by holding Space from the trigger pull until enough bullets have left.

### FAMAS (`weapons/famas.lua`)

* Record: PX's own (`weps/famas.wep`): a hidden-bullet projectile
  (`missile.sprite = 0`), no gravity, a 5000 ms fuse, and a 13-damage / 250-push
  blast.
* Burst: one `fire_sequential_actor` per trigger pull, four frames apart:
  three rounds, three, three, then two. The fourth pull plays `famas-2.wav`
  and dry-fires after its second round; the magazine resets.
* Handling: `handling.ends_turn = false` keeps the worm aiming between pulls,
  as PX's `SetState(WS_AIMING)` does; the player ends the turn after the
  magazine.
* Flight: straight at PX's 23 px/frame; the first worm, mine, crate, barrel or
  terrain it meets takes the record's blast, and it is gone after 250 frames.
  Terrain uses `wa.land.trace`; thin 1 px walls can be skipped (issue #3). The
  red bullet turns along its flight and leaves a red-orange trail.
* Art: PX's FAMAS cell 2 while aiming and cell 3 while firing, over the PX
  weapon-less posture. `fires = { subtype = 4 }` names the minigun fire pose.
  The bullet is the 32x32 red `redWeapSheet` stand-in; PX's 12-frame sheet is
  not in the workspace.

## The gun art: `spec.hold` plus a two-state fallback

The guns' 90x90 cells use the engine's `spec.hold` for **aiming**, which is
also where PX's pick animation lives: `worm_hold::grow()`
(`crates/engine/src/worm_hold.rs:121-135, :351-355`) is PX's `scale_pick`
(`worms_anims_script.txt:231-258`), so the gun grows in over the first 20
aiming frames. `spec.hold` also has the put-away, live aim, facing and
mirroring; none of that is re-implemented here.

The one gap is the firing frames of WA's own repeat-fire loop. The engine's
firing branch needs `h.firing` (`worm_hold.rs:258-263`), and `h.firing` is set
only by `worm_hold::on_fire`, from the turn's fire message (`:139-145`,
`crates/engine/src/physics.rs:1243`). A held burst's repeats come from WA's own
fire loop and send no new message, so from the second shot on the firing frames
(0x6A/0x6B) hid the gun while the aiming frames still showed it: the
intermittent missing aim.

`lib/px_hold_art.lua` now draws the same cell **only on 0x6A/0x6B**, through
the same GPU queue, at the same depth (0x10000, `worm_hold.rs:18`) with
`worm_hold::place`'s transform (`:268-300, :337-370`) and `render::Sprite`'s
rotation and mirror (`crates/render/src/geom.rs:49-111`). The gate is
`worm.state_id`, not `worm.state`: WormForge names only a subset of WA's
states, and several raw values come back as `nil`
(`crates/lua-host/src/actor.rs:2189-2207`). Aim and facing are read from the
worm every frame, so micro-adjustments and scripted flips move the gun through
the burst, as PX's `FireFinal` rebuilds its shot each loop. PX's firing branch
sets `counter = 18` and `scale_pick = scale` (`worms_anims_script.txt:280-283`),
so the fallback draws at full size; there is no pick animation in the firing
states. Presentation only: no simulation writes, no clock, no random.

The burst interval is `SHOT_DELAY = 4`, all four weapons: the log's `on_fire`
frames (879, 883, 887, 891) show WA's own fire cycle for these records, and
PX's loop inherits it. Firing one per frame ran the burst four times too fast.

## Checking

```
compiler-cli/target/release/wfcheck.exe --strict API-4.0/px_fire_seq
python porting-analysis/tools/check_paths.py API-4.0/px_fire_seq
```

`wfcheck` cannot see a broken sprite path; `check_paths.py` is the check for
that. A bad path makes the loader report `install: ... os error 2` and the game
fall back to plain WA.

`test_fire_seq_cancel.lua` is a plain-Lua harness for `seq.cancel` (fengari):
it checks that a cancel ends the counters at once, settles `on_done` once with
the number of shots already fired, and lets the next burst start.

`test_fire_while_holding_megashark.lua` stubs the sequencer and checks the
weapon's own choices: the 20-shot infinite cap, the finite ammo write on
`on_done`, and that releasing Space cancels the burst once.

`test_famas.lua` stubs the sequencer and checks the 3/3/3/2 magazine, the
sounds, the hold/firing cells, and the 13-damage / 250-push blast.
