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

Highlander never touches the **not pooled** slots, except the Hot Air
Balloon: every turn it gives the worm's team 3, as PX does. The others keep
whatever ammo the scheme gives, so the scheme decides whether Teleport or Skip
Go is always available.

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
| ming_vase | Priceless Ming Vase | the stock vase under PX's name |

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
| minigun | Burst Rifle | icon, the worm aiming it, taking it out and firing it (`weaponfire*`) |
| mortar | S.M.A.R.T Bomb | icon, flight and cluster sprites, the bits' own sprite while they home, trail, worm |
| homing_pigeon | Blaster Worm | icon, flight and cluster sprites, the bits' trail, worm |
| battle_axe | Thumper Nade | icon, flight and cluster sprites, both trails, worm |
| carpet_bomb | Thumper Nade Strike | icon, the Thumper Nade's flight and cluster sprites and trails |
| air_strike | Mortar Strike | icon, cluster sprite, both trails (stock mortar shells) |
| mole_bomb | Gravler | icon, dive and dig frames, worm |
| mole_squadron | Gravler Strike | icon (the Gravler's frames) |
| aqua_sheep | Ghost Sheep | icon, its two sprites |
| sheep | Pogo Sheep | icon, flight and cluster sprites (the Blaster Worm's bits' trail) |
| mb_bomb | Banana Express | icon, the banana plane (`plane`) |
| shotgun | Real Shotgun | icon; five pellets per shot (`fire_repeat = 5`) |

All eighteen were played in game.

**Trails.** PX draws the last three weapons' trails by overriding stock
sprites their records point at: the Salvation Army's `wsv*` frames (249-252),
free here because the Ferret holds that slot. The pack does the same with
`sprite_overrides`, for the whole match, using the trail art from PX's
`sprite_curtis_<id>` libraries. The Gravler (245-248), Ghost Sheep (156/157)
and Mortar Strike (260, 466) have their art on overridden stock sprites the
same way; PX's scripts for them do nothing else.

**Strikes** keep their bomb's art 0x14 further along than a projectile does
(+0x74 bomb, +0x7C trail, +0x138 bits, +0x140 bits' trail). The importer and
`sprite` / `cluster.sprite` follow them there. A strike's plane is at +0x38:
PX's record names the Banana Express's 704, an id PX adds past WA's last
sprite (696), so the importer keeps the slot's own plane there and the pack
gives it the banana plane with `plane`.

**The Real Shotgun** has no art of its own. PX's script calls the shotgun's
fire five times per shot; `fire_repeat = 5` does the same, five pellets in one
frame, each spread by WA's own hitscan cone.

**Old Woman Launcher's record differs from PX's in one field.** For a
projectile, +0x34 picks the worm's aim sheet (0x51C060). WA knows values 1 to
12 only, and for PX's 0 it draws no worm at all. The pack's copy has 3, the
bazooka hold, as the Cow Launcher's.

### PX weapons with a small script

| Slot | Weapon | Art | Script |
|---|---|---|---|
| holy_grenade | Hellish Hand-Grenade | icon, flight sprite, worm | none: PX draws its hold and grenade at run time, and the pack uses sheets |
| skunk | Remote Roller | icon, flight sprite, worm | none: the library's script is empty in the extract |
| homing_missile | Igniter | icon, the hold, PX's bullet | the hold and the bullet drawn at run time |
| grenade | Sticky Bomb | icon, the bomb and its bits | the hold, drawn at run time |
| fire_punch | Fire Jump | icon | PX's jump timeline |
| pneumatic_drill | Super Drill | icon | a second hole each frame |
| longbow | Shadow-Bolt | icon, the hold, the bolt, its trail | the hold and the bolt drawn at run time |
| handgun | Sniper Rifle | icon, the hold, the firing poses, laser.png | the hold, the laser sight and its own shot sound |
| jet_pack | Helicopter | icon, the helicopter, the climb-in, sounds | PX's flight, fuel and crashes on WA's jet pack |
| parachute | Hang-Glider | icon, the glider, its pack-away, its two sounds | PX's glider flight on WA's parachute |

Played in game: the Fire Jump, the Sticky Bomb and Igniter holds, the
Shadow-Bolt, the Sniper Rifle and the Helicopter.

**Holds drawn at run time.** For some weapons PX draws the worm holding it
with its sprite builder, not from a sheet. It takes a posture with no weapon
in it, then draws the weapon and a hand over it, placed and turned from the
aim each frame, and grows the weapon in as aiming starts. The pack does the
same with two GPU actors per aiming worm, from each weapon's numbers in its
PX script (`PX_HOLDS` in `rules.lua`). This needs `worm.aim` and
`worm.aiming` (engine branch `worm-aim-reads`), and without them it does
nothing. For the weapon to draw in front of the worm, it also needs
`gpu-depth-order`.

**Sticky Bomb.** PX's record leaves the bomb's sprite 0. That gives a
grenade-type slot no throw sheet, so the pack keeps the stock grenade sprite
and overrides it with PX's bomb. Its bits, once stuck, draw with the
Salvation Army's frame 467, which PX overrides too; so does the pack.

**Fire Jump.** This is WA's fire punch, whose speed then follows PX's
timeline:

- up at 9 pixels a frame at once;
- forward at 4 after 30 frames;
- 1 more upward at 60 frames;
- until 210 frames, a fall faster than 5 goes back to 4.

PX counts from `FireFinal`, which WA calls after the punch's wind-up, so the
pack starts counting when the worm starts rising. WA keeps the worm in its
punch state until it stops, so the punch cuts terrain and burns worms all the
way up. The full analysis is in `docs/px-reverse-engineering.md`.

**Super Drill.** WA drills as usual, and a hidden actor cuts a second drill
hole at the worm each frame until WA's drill stops.

**Missiles drawn at run time.** For some weapons PX leaves WA's flight
sprite 0 and draws the missile itself (`WeapSprite`). The sprite is turned
to its flight, mirrored when it flies left, and can be animated. The pack
does the same with a GPU actor per missile, placed from
`wa.on.missile_frame`, and uses each weapon's numbers from its PX script
(`PX_WEAP_SPRITES` in `rules.lua`). It needs `m.weapon`, the missile's slot
(engine branch `missile-weapon`). The Shadow-Bolt's bolt is drawn this way,
its hold is animated, and its trail is stock sprite 453 with PX's shadow
trail, as `sprite_curtis_453` does.

**Sniper Rifle.** While the current worm aims it, PX's laser sight is drawn
every rendered frame from `wa.on.draw`, as `wa.draw.quad`s (engine branch
`draw-quad`), following PX's `laserray` point for point:

- 100-pixel additive quads of `laser.png` along the aim;
- narrowing along the ray, with PX's brighter start and faint 7-pixel tip.

It stops at terrain, traced exactly, and at worms, mines, crates and
barrels. PX stops it with a 2x2 collision mask, so the object radii here are
estimates. Two differences from PX:

- **The aim:** the ray uses the aim the rifle was drawn with, so the two
  always turn together. `worm.aim` is WA's smoothed crosshair, and WA
  rewrites it at render time (see `docs/px-reverse-engineering.md`).
- **The start:** the ray starts on the barrel, 2 pixels off the worm's
  centre line where PX starts it, because the art's barrel runs 2 pixels to
  one side.

The rifle fires with PX's own shot sound, `sounds/sniper_firing.wav`, and
the worm fires it in the `snipefire` poses the scheme's record names; left
out, WA drew its own handgun for the shot.

A few things differ from PX on purpose, for weapons drawn at run time:

- **Putting it away.** PX drops the weapon the frame the worm stops
  aiming. WA puts it away by playing the worm's draw backwards (see
  `docs/px-reverse-engineering.md`), so the weapon shrinks out with it:
  PX's grow-in played backwards, over WA's 20 frames. Not after a throw:
  a thrown Sticky Bomb has left the worm's hands, and WA puts nothing away.
- **While firing.** PX hides the weapon while the worm fires. The Igniter,
  the Shadow-Bolt's crossbow and the Sniper Rifle (with its laser) stay up
  instead, over whatever pose WA fires in: the Sniper Rifle's `snipefire`
  poses are the worm lit by the muzzle, and the other two have none, so the
  worm would be empty-handed.

**Helicopter.** PX's `helicopter_user_script`, on WA's jet pack:

- **Arming:** the Helicopter is armed while WA winds the jet pack up and
  launches on the jet pack that follows, since WA may clear the worm's
  selection as it fires the team's last one. During the wind-up, PX's
  climb-in animation plays.
- **Flight:** the script flies the worm from the worm's own move keys
  (`worm.keys`) and consumes them (`worm:clear_keys()`), so WA's jet pack
  neither thrusts nor burns fuel. Speed builds while a key is held, towards
  10 pixels a frame, and dies away when it is not. Gravity and wind act at
  0.2, and Shift keeps the facing.
- **Fuel:** 100 (`worm.fuel`), burnt by flying and by each key, but not
  during retreat. WA's own fuel counter shows it, because only the worm's
  body is hidden (`worm.body_visible`), as PX's `RenderWorm` override does.
- **Crash:** when the fuel runs out, the worm reaches water, or it hits
  anything but a mine faster than a pixel a frame (`wa.on.contact`, judged
  on the speed before impact). The explosion is sized by the fuel left and
  the speed, followed by one of PX's "oops" lines. The ground counts as
  something it hits: landing slower than a pixel a frame is PX's smooth
  landing, and a faster one crashes it. When WA ends the jet pack at rest,
  the worm slides.

The engine pieces are on the `worm-flight` branch.

**Hang-Glider.** PX's `paratest` (`utility_hangglider_render`), on WA's
parachute. Opened with the Hang-Glider, the parachute flies as PX's glider:
gravity at 0.75, the wind along the wing's up side at 3x, a quarter of the
speed across the wing damped each frame, and a nose that turns towards the
flight path, at most about 86 degrees up or down. Up and down turn the nose,
faster the faster it flies; left and right push it. It needs WA's own gravity
and wind, `wa.world.gravity()` / `wa.world.wind()`. Two differences:

- Just before it would run into something, PX ends the glide with
  `WS_AFTERROPE`; the pack uses WA's sliding state, as the Helicopter does.
- PX swaps the sheet WA packs a parachute away with on flat ground
  (`wparbak`, 289) for the glider's own. The pack cannot see which sheet WA
  plays, so it hides the worm and plays the glider's pack-away, its 6 frames
  at 24 a second, whenever the glider lands on its feet.

Flight, cluster and plane sprites take 20 of the 223 shared sprite slots. Worm
sheets and `sprite_overrides` (the trails and the Gravler's and Ghost Sheep's
frames) are drawn by the GPU renderer, in true colour, and take none.

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

- PX grants 3 Hot Air Balloons and 1 Wind Changer every turn. The balloons
  are granted; the Wind Changer is not ported yet, so its slot (WA's
  Surrender) is left to the scheme.
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
- the ported slots, each from its own scheme record, with PX's art (39)
- the Fire Jump's timeline, counted from the punch, not the fire key
- the run-time holds: placed from the aim, mirrored, grown in, and dropped;
  animated, and with no hand
- the run-time missile sprites: one per missile, turned to its flight,
  animated, and only on its own weapon's missiles
- the laser sight: its start, colours, length (full, to terrain, to a worm),
  when it shows, and the shot sound
- the Helicopter: the climb-in, launch (including with the last shot),
  kicks, damping, fuel and retreat, crashes by contact and fuel, mines not
  crashing it, slow and fast landings, and the landing slide
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
