# Highlander (inventory verbs)

This is the concise implementation built on `wa.inventory`,
`wa.on.turn_start`, and `wa.on.death`. The original hand-written bookkeeping
is preserved in `highlander_pure_lua` for comparison. Enable only one edition.

Project X's *Highlander 0rang3 1.1*: its rules, on its weapon layout. The
scheme puts each of its weapons on one of WA's stock slots, e.g. the Baseball
Bat on the girder's. The pools are PX's own lists, each weapon written as the
slot it takes.

Weapons are ported in batches. **A weapon not ported yet leaves WA's stock
weapon on its slot, and that stands in for it.** For example, the Ice Arrow's
slot still holds Armageddon, dealt as a second weapon.

## Rules

- At the start of the match, every worm is dealt **one weapon from each
  pool**.
- On a worm's turn it can use **exactly its own weapons, one shot of each**.
  Nobody else holds any pooled weapon, whatever the scheme says.
- Next turn it gets them back. Firing doesn't use a weapon up for good.
- **When a worm dies, the worm whose turn it is takes everything the dead
  worm carried**, and can use it that same turn. That includes friendly and
  accidental kills, as in PX. A worm that dies on its own turn simply loses its
  weapons.
- **On cavern maps, the Ferret and nothing that falls from the sky is
  dealt.**

| Pool | Weapons (stock slot) |
|---|---|
| Offensive (29) | Double Bazooka (bazooka), Igniter (homing missile), S.M.A.R.T Bomb (mortar), Blaster Worm (homing pigeon), Burning Sheep Launcher (sheep launcher), Sticky Bomb (grenade), Windy Cluster (cluster bomb), Super Gravedigger (banana bomb), Thumper Nade (battle axe), Electric Grenade (earthquake), Dynamite, Nuke Rocket (mine), Pogo Sheep (sheep), Ghost Sheep (aqua sheep), Chilli Bomb (super banana), Hellish Hand-Grenade (holy grenade), Valyrian Fire (petrol bomb), Remote Roller (skunk), Priceless Ming Vase (ming vase), Cow Launcher (mad cow), Old Woman Launcher (old woman), Ferret (salvation army), Mortar Strike (air strike), Pigeon Strike (mail strike), Submarine Attack (mine strike), Gravler Strike (mole squadron), Banana Express (mb bomb), Bowling Ball Strike (sheep strike), Thumper Nade Strike (carpet bomb) |
| Second (19) | Fire Jump (fire punch), Sentry Laser (dragon ball), Sentry Gun (kamikaze), Javelin (prod), Baseball Bat (girder), Electromagnet (baseball bat), Real Shotgun (shotgun), Sniper Rifle (handgun), Laser Gun (uzi), Burst Rifle (minigun), Shadow-Bolt (longbow), BlowTorch, Super Drill (pneumatic drill), Portal Gun (scales of justice), Ice Arrow (armageddon), Flame Thrower, Reinforcement (nuclear test), Crate Strike (donkey), Lightning Strike (napalm strike) |
| Movement (7) | 3 Girder Pack (girder pack), Jump (ninja rope), Hang-Glider (parachute), Super Tele (teleport), Helicopter (jet pack), Gravity Control (low gravity), Swim Suit (laser sight) |
| Not pooled (14) | Kamikaze Rocket (suicide bomber), Gravler (mole bomb), Hot Air Balloon (bungee), Skip Go/Surrender (skip go), Wind Changer (surrender), Muahaha 3 (select worm), Weapon Crate (freeze), Cluster Bomb (magic bullet), Fast Walk, Teleport (invisibility), Skunk (damage x2), Crate Spy, Mole Bomb (double turn time), Crate Shower |

Highlander never touches the **not pooled** slots. Their ammo is whatever
the scheme gives, so the scheme decides whether Teleport or Skip Go is always
available.

On cavern maps PX draws from the first 21 offensive and the first 16 second
weapons only. That leaves out the Ferret and the strikes, and Reinforcement,
Crate Strike and Lightning Strike.

## Ported weapons

Each takes its record from the scheme itself (`weps/<slot>.wep`), which
carries PX's tuning for this scheme and its name. They are cut from
`HL - 0rang3 - 1.1.pxs` with:

```sh
python3 tools/px_scheme_weps.py "HL - 0rang3 - 1.1.pxs" mods/examples/highlander/weps <slot> ...
```

### WA's own weapons

| Slot | Weapon | Notes |
|---|---|---|
| dynamite | Dynamite | |
| blow_torch | BlowTorch | |
| flame_thrower | Flame Thrower | |
| girder | Baseball Bat | stock bat icon |
| girder_pack | 3 Girder Pack | three girders, not five |
| fast_walk | Fast Walk | |
| crate_spy | Crate Spy | |
| crate_shower | Crate Shower | |
| magic_bullet | Cluster Bomb | stock cluster icon |
| invisibility | Teleport | stock teleport icon |
| damage_x2 | Skunk | stock skunk icon |
| double_turn_time | Mole Bomb | stock mole icon |

These are WA's own weapons. Moving one to another slot works only as far as
WA reads the weapon from its record rather than its slot number. Played in
game: the Baseball Bat on the girder slot aims and swings as the bat; the
Cluster Bomb, Skunk and Mole Bomb fire as their records say; 3 Girder Pack
places three; Dynamite still gives its retreat time. Open points:

- **Teleport on the invisibility slot:** WA disables Invisibility's slot in
  offline games, so the Teleport is unavailable offline. Not yet checked
  online.
- **The scheme's header fields** (the dwords before the fire type) do not
  match WA's stock values. For example, Dynamite's retreat time is 0, not 5 s,
  and the bat's first flag is 0 where WA's is 1. The whole record is imported,
  as PX writes it; neither weapon plays differently for it.

### PX weapons that need only PX's art

None of these has a script in PX. The icons are PX's files byte for byte,
so replays share them. The strips are split into frame folders with
`tools/px_split_strip.py`.

| Slot | Weapon | Art |
|---|---|---|
| sheep_launcher | Burning Sheep Launcher | icon |
| mad_cow | Cow Launcher | icon |
| old_woman | Old Woman Launcher | icon |
| mail_strike | Pigeon Strike | icon |
| cluster_bomb | Windy Cluster | icon, cluster bits |
| banana_bomb | Super Gravedigger | icon, flight and cluster sprites, the worm holding and taking it out (flat, up, down) |

All six were played in game.

**Old Woman Launcher's record differs from PX's in one field.** For a
projectile, +0x34 picks the worm's aim sheet (0x51C060). WA knows values 1 to
12 only, and for PX's 0 it draws no worm at all. The pack's copy has 3, the
bazooka hold, as the Cow Launcher's.

The Windy Cluster's bits and the Super Gravedigger's flight and cluster
sprites take 3 of the 223 shared sprite slots. The worm sheets are drawn by
the GPU renderer and take none.

The Burst Rifle needs its own aim, draw and fire poses, which the engine's
worm-sheet remapping does not cover yet (only the bazooka, flamethrower and
throw poses). It is left for its own change.

## Playing it

1. Enable only this pack in the mod loader. Packs that replace a stock slot,
   such as `sentry_gun`, `pooz` or `worm_toss`, would put their weapon into the
   pool in place of the one there.
2. Any scheme works. The pooled slots are overwritten every turn, including
   ones the scheme has at infinite.
3. `wkLua.log` records every hand dealt, by slot, and every weapon taken:
   `highlander: worm 16 took ... from worm 32`.

## Differences from PX

These are deliberate, and each one is explained in `rules.lua`:

- Wind Changer and Hot Air Balloon are not ported yet, so nothing is granted
  in their place.
- There's no removal at turn end. The next turn start does the same job.
- Every pooled slot is zeroed at each turn start, not only the previous
  worm's. PX left that to its own scheme; here any scheme works.

## Lockstep

The pack uses lockstep `worm_message`, `turn_start`, and `death` events.
Every random choice is `wa.random()`, which draws from WA's shared RNG, and
hands are dealt in worm-message order. Two peers, or a replay, deal the same
hands. Nothing reads local input or the clock.

## Reusable engine features

- `worm:ammo(name, { set = n })`: an absolute ammo write, WormForge's
  version of PX's `SetWeaponEx`. The older `worm:ammo(name, n)` adds to
  the current ammo and never changes infinite.
- `wa.inventory.create({ id, slots })`: a pack-scoped, per-worm virtual
  inventory. Its `deal`, `transfer`, `clear`, and `apply` verbs are usable by
  class/loadout mods without copying Highlander's bookkeeping.
- `wa.on.turn_start`: the active worm as a first-class lockstep event.
- `wa.on.death`: one event per death with `victim`, current `active`, and
  optional proven `attacker`, `attacker_team`, `weapon`, `slot`, and damage
  `kind`. Highlander intentionally transfers to `active`, preserving PX rules.
- `wa.on.hurt` carries the same optional attribution fields, so a different
  pack can transfer on damage or only for a particular weapon.
- `wa.world.cavern()`: WA's own cavern flag (`GameWorld+0x777C`).
- A fix: granting ammo used to move the weapon into the F1 panel row. It now
  stays in its own row.
- A fix: ammo **writes** went to the wrong row. The engine read a team's
  alliance from a different field than WA's own `GetAmmo` does, so every
  team's writes landed in the first team's row. Only that team ever played by
  Highlander rules.

## Tests

```sh
lua mods/examples/highlander/test_rules.lua     # from the repo root
```

These run `rules.lua` against a mocked WA. Ammo is stored per alliance, and
the mock scheme has an infinite bazooka. Which row a team's writes land in is
the engine's job, and the mock can't test it. They cover:
- the ported slots, each from its own scheme record, with PX's art
- pool coverage (55 pooled slots, and the 15 others never touched)
- deterministic dealing, including worms that appear late
- cavern hands (PX's short ranges)
- per-turn ownership and taking weapons back
- a stolen hand usable the same turn and kept afterwards
- friendly kills
- no double transfer
- a worm dying on its own turn

The inventory/rule-event refactor is covered by this mock suite and still
needs an in-game validation after deploying the matching DLL and pack.
