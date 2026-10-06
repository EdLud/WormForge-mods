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

Most start from the stock WA table entry (`copy_from = "<slot>"`) with a
named `patch` for the fields PX's scheme changed. Lightning Strike and
Electric Grenade use the scheme's full `.wep` records, extracted with
`tools/px_scheme_weps.py` from `HL - 0rang3 - 1.1.pxs`.

### Electrical weapons

| Slot | Weapon | Behavior |
|---|---|---|
| napalm_strike | Lightning Strike | Cursor-aimed 30° beam, 150-frame warning, 16-frame strike, 60-frame tail; heals live worms, revives linked graves at 10 HP, arms mines, and hits crates/oil drums. |
| earthquake | Electric Grenade | WA grenade flight and explosion followed by PX's seeking, terrain-following, chaining tazer arc; delayed 24 damage to worms and 12 to objects, mine arming, and a temporary tazed pose. |

The beams, glows, and explosion use the GPU atlas. Gameplay runs in simulation
callbacks; drawing only varies presentation. A grave records its original worm
ID when WA creates it. On revival, Highlander restores the dead worm's saved
hand while the active worm keeps the weapons it gained at death. PX's sentry
ownership transfer is deferred.

### Super Tele

Super Tele replaces the teleport slot with the scheme's type-3 cursor weapon
and PX icon. The click position is held for 50 game frames while WA plays its
teleport animation, then the worm moves there. Three 12-pixel terrain cuts at
the click and 10 and 22 pixels above make room to arrive inside land. Cavern
clicks are clamped to 19 pixels below the ceiling, as in PX. The click comes
from WA's synchronized fire context, so the destination cannot follow a
later mouse movement.

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
| handgun | Sniper Rifle | icon, the hold, the firing poses, laser.png, a muzzle flash | the hold, the laser sight, a muzzle flash and its own shot sound |
| jet_pack | Helicopter | icon, the helicopter, the climb-in, sounds | PX's flight, fuel and crashes on WA's jet pack |
| bazooka | Double Bazooka | icon | a second shell from where the first explodes |
| mine | Nuke Rocket | icon, the rocket, the hold, the launch sound | a nuke climbs out of the fusing rocket |
| super_banana | Chilli Bomb | icon, the chilli (held and in flight) | five more Chillis burst out of it and burst into fire |
| laser_sight | Swim Suit | icon, the swim and float animations, the bubble, its sound | PX's swimming on WA's laser sight |
| surrender | Wind Changer | icon, three wind sounds | 0-9 choose the force, firing sets the wind |
| uzi | Laser Gun | icon, the worm aiming and taking it out, its beam and glow, three sounds | PX's 5 s beam in place of the uzi's bullet |
| low_gravity | Gravity Control | icon, its two sounds | 1-5 choose the gravity, firing holds it for the turn |
| ninja_rope | Jump | icon, the worm aiming it | the worm leaves with the shot's speed |
| parachute | Hang-Glider | icon, the glider, its pack-away, its two sounds | PX's glider, flown by the pack once WA's parachute opens |

Played in game: the Fire Jump, the Sticky Bomb and Igniter holds, the
Shadow-Bolt, the Sniper Rifle and the Helicopter.

**Holds drawn at run time.** For some weapons PX draws the worm holding it
with its sprite builder, not from a sheet. It takes a posture with no weapon
in it, then draws the weapon and a hand over it, placed and turned from the
aim each frame, and grows the weapon in as aiming starts. Each replacement
declares its PX numbers as `hold = {…}` (`PX_HOLDS` in `lib/holds.lua`); the engine
draws the GPU weapon and optional hand over WA's worm pose. Walking hides the
hold immediately, and aiming restores it. Holds are presentation only and do
not spawn simulation actors.

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
(`PX_WEAP_SPRITES` in `lib/missile_sprites.lua`). It needs `m.weapon`, the missile's slot
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
- **A muzzle flash.** PX's Sniper Rifle has none. Each shot lights the
  sentry gun's flare, smaller (0.45), at the rifle's tip for 3 frames:
  additive and white, turned with the aim.

**Double Bazooka.** PX's `double_bazooka_script`:

- **The first shell** explodes as WA's own. PX then cuts a 50-pixel hole
  there (`MakeHole`, as `wa.land.dig`) and fires a second shell from it at
  the first one's speed.
- **The second shell** is a real WA missile of the same slot, launched with
  `wa.weapons.launch`, as PX's script creates a `CMissile` from the weapon's
  launch data. So WA flies it with wind and its smoke trail. It takes PX's
  damage 40 and 5 s fuse, and its own explosion ends it. PX also gives it
  sprite 54, which is a cluster bit (`clustlet`) in WA 3.8.1, so it keeps
  the record's bazooka shell instead.
- **The worm holds a plain bazooka.** The scheme's record gives the Double
  Bazooka the homing missile's recoloured launcher (`wbaz2`, 7 at +0x34);
  the pack's copy has the bazooka's own (3).
- **Not ported:** PX's particle trail on top of WA's, and a plain 50/35
  blast PX makes when a second shell explodes before its first frame.

**Nuke Rocket.** PX's `nuke_rocket_script`, on the mine slot:

- **The rocket** is WA's own shot. The scheme's record is a placed weapon
  that WA fires as a missile, and it already has what PX's `FireFinal`
  gives the rocket: a 3 s fuse, no damage, WA's `Fuse` sound. It sits on
  the ground fusing, and PX adds the hiss every 10 frames.
- **The nuke** climbs out when it explodes: PX's launch sound, then a real
  WA missile of the slot (`wa.weapons.launch`), silent, with a 1.6 s fuse,
  bursting into the record's clustlets. For 53 frames it climbs, randomly
  and jittering sideways, carrying worms and missiles within 17 pixels
  along; then it brakes. Its explosion adds WA's sounds 85 and 70 and two
  40/40 blasts.
- **The hold** is PX's sprite builder with a fixed angle
  (`dont_rotate_with_angle`): the rocket and a hand, placed as if aimed
  level and turned by PX's fixed angles, whatever the aim.
- **Not ported:** PX's particle trails, and carrying mines, crates, oil
  drums and bowling balls.

**Helicopter.** PX's `helicopter_user_script`, on WA's jet pack:

- **Arming:** the Helicopter is armed while WA winds the jet pack up and
  launches on the jet pack that follows, since WA may clear the worm's
  selection as it fires the team's last one. During the wind-up, PX's
  climb-in animation plays.
- **Flight:** the script flies the worm from the worm's own move keys
  (`worm.keys`). The engine consumes the keys after the script reads them
  (`worm:jetpack_steer(true)`), so WA's jet pack neither thrusts nor burns fuel.
  Speed builds while a key is held, towards
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
  WA owns the landing state; the script restores the worm's body and normal
  gravity when the jet pack ends.

**Chilli Bomb.** PX's `pyro_grenades_script` (PyroMan), on WA's super
banana. When it explodes, five more Chillis burst out of it, straight up with
a random spread: real WA missiles of the same slot (`wa.weapons.launch`), each
with damage 30, an 8 s fuse, no countdown, the fire key setting it off, and a
burst of fire where it ends. They do not burst again: a missile PX's script
makes has no weapon of its own. PX draws the chilli turned to its flight
and leaves WA's sprite 0; so does the pack. The record keeps WA's banana,
because a thrown weapon's worm posture is picked by its sprite, and each
missile's own copy is set to 0 in flight instead (`m.sprite`). Not ported: PX's particles, the five's smoke trail power
of 20, and PX writing the five's changes into the weapon's own launch data,
so that every later Chilli Bomb flies with them.

**Swim Suit.** PX's `swimsuit_SCRIPT` (StepS), with `fastswim_SCRIPT` and
`swim_suit_diving_s` (PyroMan), on WA's laser sight, which never switches on.
Worn, a worm that falls into the water swims instead of drowning:
- **Swimming:** it is held in WA's bungee state with no gravity and moved by
  its own four keys, up to 2.5 pixels a frame times the swim speed, and glides
  to a stop when they are let go. Left and right turn it unless Shift is held.
  Enter does nothing while it swims.
- **Leaving the water:** out of the water it flies on as from a jump. Too deep,
  or knocked out of those states, the suit gives out and it sinks.
- **Speed:** Fast Walk switches the swim speed between 2 and 6 for the turn.
- **Missiles:** a missile in the water blows up on a swimming worm (100, 50).
- **Looks:** the swim or float animation is drawn in its place, with a bubble
  drawn in `wa.on.draw` from live worm.x/y while the suit is worn (no ring actor).
- **Engine pieces:** `worm.collision_mask` and `m.collision_mask`, and the
  `bungee` and `sinking` states.
- **Not ported:** PX's ghost-jet and battyswim interplay, the Ninja Rope
  workaround (the Jump is on that slot), inverted controls, and the team
  message.

**Laser Gun.** PX's `lasergun` (`CLaserRay`), on the Uzi's slot. Its record
is an uzi firing one bullet; no bullet leaves, and a beam burns from the worm
along its aim for 5 s, the worm held firing (aim live) for as long:
- **Every fourth frame** it traces to the first land, up to 2048 px, cutting
  4 px holes there, along the cut while the aim holds still.
- **Damage:** everything within 5 px of it takes fire damage: a worm 2, then
  1 once it has taken 10, and no more than 45 from one beam; an oil drum 4, a
  crate 1.
- **Looks:** a red strip pulsing from full width to half, glows at the muzzle
  and the hit, red sparks from the muzzle, glows rising from the cut, yellow
  sparks on what it touches.
- **Differences:** a mine it touches is armed on its fuse once, rather than
  taking PX's gun damage; the loop sound is replayed every 51 frames.

**Wind Changer and Gravity Control.** PX's `wind_changer_script` (ravander,
improved by 0rang3) and `gravity_control_script` (DabbyB, edited by 0rang3).
Both records are one of WA's turn utilities with an index WA doesn't use, so
WA fires a utility that does nothing and the script does the work:
- **Wind Changer:** while it is selected, 0-9 choose the force. Firing it sets
  the wind to force × 0.0317 towards where the worm faces, through WA's own
  wind change (the clouds and the wind bar follow). The rules grant one every
  turn, as PX's GiveWeapons does.
- **Gravity Control:** 1-5 choose 0.3, 0.5, 1, 1.7 or 2.4 times the match's
  gravity. Firing it holds WA's gravity there until this turn ends. Fired with
  nothing chosen, it doesn't fire.
- **Keys:** the digit keys are synced like the other keys.
- **Differences:** a HUD line shows the keys and the choice, in place of PX's
  team messages. PX also puts the gravity back after 10 s with the turn clock
  stopped; that isn't ported.

**Jump.** PX's `jumpscript` (`utility_jump`), on the Ninja Rope's slot. Its
record throws like a grenade, but nothing leaves the worm:
- **Firing:** the worm itself leaves with the shot's speed, from the aim and
  the charge, and says its team's "Jump" line.
- **Aiming:** the worm looks along the aim (PX's `eyes` sheets) until it
  jumps, charging included.
- **Differences:** PX shows WA's `wjump` crouch while the charge builds, which
  looks ahead rather than along the aim. PX also mutes the worm's "Fire!" and
  "Watch this" lines while the Jump is selected, and stops a fuse or bounce
  being chosen for it.

**Hang-Glider.** PX's `paratest` (`utility_hangglider_render`). Opened with
the Hang-Glider, WA's parachute becomes PX's glider: the pack takes the worm
(`worm:take`) and flies it itself, with gravity at 0.75, the wind along the
wing's up side at 3x, a quarter of the speed across the wing damped each
frame, and a nose that turns towards the flight path, at most about 86 degrees
up or down. Up and down turn the nose, faster the faster it flies; left and
right push it. It needs WA's own gravity and wind, `wa.world.gravity()` /
`wa.world.wind()`.
- **Ends:** just before it would run into something (PX's `WS_AFTERROPE`;
  land by WA's own test of the worm's shape, `worm:fits`), on
  the jump key, in water, or when the turn ends, the worm goes back to WA
  (`worm:release`) falling on with the glider's speed, and WA lands it.
  Weapons fire from it as from WA's parachute.
- **Landing:** PX swaps the sheet WA packs a parachute away with (`wparbak`,
  289) for the glider's own. Here WA never packs a parachute away: when the
  glide ends coming down onto land below WA's 8-pixel-per-frame fall-damage
  threshold, the glider's pack-away (6 frames at 24 a second) plays once WA
  has the worm standing. A faster impact releases the worm at full speed into
  WA's normal falling state, so WA can apply the scheme's fall damage and
  loss of control. During that impact, the engine masks the parachute slot
  inside the worm's frame handler so it cannot reopen and slow the worm; the
  selected weapon is restored afterwards. A hard landing or a crash into
  something ahead plays no pack-away.

**Hot Air Balloon.** PX's `balloon_s` (r2_balloon by rafa''2, modified by
0rang3), on the Bungee's slot, whose record the pack patches into a parachute.
PX flies it on WA's parachute with the worm's gravity turned upside down.
Here the pack takes the worm when that parachute opens and flies it with WA
3.8.1's own parachute physics, upside down:
- **Physics:** each frame the speed gains gravity (upward) and the wind, then
  both are damped to 0.8. These are WA's entity physics (0x4FCB30) with the
  parachute's damping and wind factor (SetState 0x7D, 0x50EBE2 and 0x50EC57).
  So it rises at up to four times gravity and drifts with four times the wind.
- **Steering:** the arrow keys push it as they push WA's parachute (0x513EB0):
  half of gravity a frame in the key's direction, opposite keys cancelling.
- **Pops:** on touching land, in water, on the jump key (which closes WA's
  parachute), and when the turn ends. The worm then goes back to WA, falling
  with the balloon's speed. Weapons fire from the basket as from WA's
  parachute.
- **Art:** the worm's body is hidden behind the balloon, drawn in its team's
  colour, and the worm in its basket, as PX's `RenderWorm` override draws them.

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

These are deliberate, and each one is explained in the pack's code:

- PX grants 3 Hot Air Balloons and 1 Wind Changer every turn; so does the pack.
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

## Layout

`rules.lua` is the entry: the pack's description and one `require` per
module, in the order they run.

| Folder | Holds |
|---|---|
| `lib/` | What several weapons share: the engine-drawn holds, sprite animation helpers, PX's missile sprites, and `shared.lua`, the table modules pass values through. |
| `weapons/` | One module per weapon or weapon family, plus the claim tables (`catalog.lua`, `claims.lua`) and the generated record data (`wep_data.lua`, written by `tools/embed_weps.py`). |
| `scheme/` | The Highlander scheme itself: its pools, its state and its rules. |

A module reads another's value as `local name = shared.name`; one that is
set later (an explode handler the claims call) is used as `shared.name`
throughout. `tools/split_highlander.py` made this layout from the single
`rules.lua` the pack used to be, and can make it again from a newer one.

## Tests

```sh
lua mods/examples/highlander/test_rules.lua     # from the repo root
```

These run the pack (`rules.lua` and the modules it requires) against a mocked WA. Ammo is stored per alliance, and
the mock scheme has an infinite bazooka. Which row a team's writes land in is
the engine's job, and the mock can't test it. They cover:
- all 54 slot claims, including the Lightning Strike, Electric Grenade,
  Laser Gun and Super Tele scheme records
- Super Tele's exact click, 50-frame wait, three terrain cuts, cavern ceiling
  and cancellation when its worm dies
- strike timing, grave identity, revival and restored Highlander hand
- tazer seeking, delayed zap, stun, mine fuse, object damage and terrain trace
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

### Javelin (prod)

Uses Highlander 0rang3 1.1's weapon record and the sprite-builder edition's
12-frame hold and flight animations. Stock WA flies the projectile. On impact,
Lua thrusts the first worm, mine, crate or oil drum in PX's strict 20-pixel
square, with 20 damage and a quarter of the incoming velocity. Mines handle
the impact through WA's mine handler. The active worm has PX's 25-pixel fallback.

If nothing is hit, `wa.land.stamp` embeds one of the 32 oriented 60×60 frames
into actual terrain. It stays solid, can be walked on and destroyed, and needs
no persistent actor. PX's ratio-based orientation bins are preserved. The
stamp uses source alpha and the colours the terrain already holds; airborne
art uses GPU sheets. Terrain writes and target selection run only during
simulation. The impact sound plays on the turn's worm (PX plays it unplaced):
an explosion's `ev.worm` is the missile's owner, not necessarily a worm.
