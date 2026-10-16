# Offline stock weapon audit

This diagnostic fires real WA weapons through `worm:input`, not their Lua
handlers. **Audit home** places all 70 stock weapons at home; **Audit copies
past 70** places a plain copy of each, every one past WA's 70 slots. A
difference between the two is something WA ties to the slot id. Each fired weapon receives infinite ammo at case setup; instant utilities receive one stocked item without a fire input. Delays are zero, crate weights zero,
and their records do not end the turn. Native special weapons may still end it.

Build the diagnostic DLL explicitly:

```sh
bash tools/build-win32.sh --variant diagnostics
python3 tools/install-local.py --variant diagnostics
python3 tools/audit_map.py tmp/input-verb/Audit.png
```

`diagnostics` is disabled by default. Only that build exposes `wa.audit` and
contains the RNG fixture hook. The add-on refuses to run without it. Both
fixtures and `worm:input` require the bundle's `debug_input = true`, run only
inside simulation callbacks, and are refused in network rounds. The engine
logs a TEST BUILD banner. An ordinary release has no RNG-control API.

Copy the `tools` bundle to `WormForge/Mods/`, preserving local edits. When
installing by copying files, also copy its `profiles/Audit*.toml` files
into `WormForge/Profiles/`; the profile dropdown reads that folder. In the
WormForge loader, enable the `example.tools` bundle and select **Audit home**
in the Profile dropdown. A WA scheme controls match settings; it does not
select a WormForge profile or enable the audit add-on. Import
`Audit.png` from `User/SavedLevels/` into WA's map editor. Save an **Audit**
scheme with the settings below, and select this same saved map for every run.
Use three human teams with three 100-health worms each, team 3
reserved for Surrender. Disable random turn order, mines, oil drums, crate
drops, sudden death and automatic utilities; choose a long round and turn
time (90 seconds or longer). Keep the same teams, scheme, map, renderer and
settings for every run. The 7680x5376 indexed map has 70 identical flat
platforms, 768 pixels between station centres, plus a reserve platform for
waiting worms. Its fixed seed is 20261015.

Restart WA after installing the DLL. Start **Audit home** offline. The add-on
checks the roster and map dimensions/stations on a simulation frame after the
first worm's turn becomes active, moves the waiting worms to the reserve,
and runs automatically. Any team may start: the audit skips ordinary turns
until team 1's first worm receives its turn, then begins the first case.
Keep physical keys released during the test. Save
`wkLua.log` after the HUD says `Audit complete`; a stopped/error audit is not
a complete comparison. Then run **Audit copies past 70** from the same scheme,
with the same teams. Save each log separately.

**Copies past 70.** The `tools` bundle also has a plain copy of each of WA's
weapons (`tools.copy_<name>`, `copy_from` and nothing else). **Audit copies past
70** places the copies alone, each on a slot past WA's 70 as every weapon that
isn't WA's own, and the add-on's `copies` option fires each case's copy
in place of WA's own; WA's own Skip Go still ends the turns, and WA's own Bazooka stays
on slot 1 with infinite ammo, as at home: after a shot WA does not re-select, it
selects whatever is on slot 1, and both runs need the same there. Its signals keep
the stock names, so it compares with a home run:

```sh
python3 tools/audit_compare.py home.log copies.log
```

A difference is something WA ties to the slot id: what a weapon past 70 does
not get. Compare two home runs as well: what differs between them is the
audit's run-to-run spread (WA draws much of its randomness from the absolute
frame counter), not a slot tie. On 2026-10-15 only the four turn-start instant
utilities (Damage ×2, Crate Spy, Double Turn Time, Crate Shower, used from
slots 67..70) differed beyond that spread.

The comparison selects the last audit session in each file by default;
`--home-session 1` / `--moved-session 1` select explicit sessions. Exit 0 means
equal, 1 differences, 2 incomplete/incomparable. It compares structured
`audit:`/`audit-native:` signals and native `state` transitions, ignoring
pointer addresses and absolute match frames, and marks the cases after the
first difference `after a difference`.

WA draws most of its random numbers inline from the absolute frame counter,
so the RNG fixture can't make two rounds' spread identical. The comparison
therefore normalises each case first (see `tools/audit_compare.py`): each
kind of event and each worm role (`self`, `other`) is its own sequence; the
opening turn's leftovers before `setup` are dropped; the first missile of a
weapon (the launch) keeps its position and speed, later fragments, explosions,
hurts and bodies only what doesn't move with the spread; the land digest
becomes "this case changed the land". A case that differs only in those
spread kinds is marked `spread only`; the last line lists the others, the
slot-tie candidates. `--strict` compares the signals exactly as logged. Every
pre-existing weapon claim is still covered by the claims snapshot.

Each firing case records its initial terrain/ammo, moves/heals/equips its worm,
sets a 45-degree aim, 3-second fuse and minimum bounce, waits 40 frames for
aiming, presses Space, and releases after 15 frames. Cursor weapons receive
a world target 160 pixels to the right. Shotgun/Longbow receive another
press; animals get secondary presses; Rope, Parachute and Jet Pack
receive their own movement/release sequences. Bungee is selected on land near
the edge, then walks off it with Right. Its attachment state is recorded;
Space only detaches an attached bungee. It is never warped into midair to
trigger attachment. An absent attachment is explicitly logged as uncovered.
Sheep gets its second activation at
frame 90 (explode). Super/Aqua Sheep activate flight at frame 90, steer left
then right, and get the third activation at frame 140 (release). These are
native active-weapon messages, not another shot of the fallback selection. After 280 frames, 25 quiet
frames complete the case; 1000 frames is the timeout. Terrain is hashed from
short land traces at eight-pixel intervals around the station. All stock
missile constructors and explosions are recorded natively, including a
missile that bursts before its first frame. Strike/crate missiles whose
native provenance is unavailable are explicitly `null`, not guessed.

Destructive cases run last: Kamikaze, Suicide Bomber, Skip Go, Select Worm,
Freeze, Nuclear Test, Earthquake, Armageddon, Surrender. Each spawns a fresh
worm and waits for WA to give it a normal turn. Fresh cases alternate between
teams 1 and 2 to stay within WA's eight-worm team limit. The scheduler skips intervening
worms using the placed Skip Go; it never grants or forces a turn. Surrender
uses team 3 exclusively. Cases end at the firing worm's turn end/change or
removal, even if later effects continue. Such later effects can affect a
subsequent case and must be considered when interpreting differences.
The pending worm and weapon are logged. Waiting stops with an error after
6000 simulation frames (two minutes), rather than cycling for ten minutes.

Hurts on audit worms are logged before returning `"eat"`. Existing hurt API
semantics skip the whole native hurt handler, including its knockback;
this audit does not validate the knockback that a cancelled hurt would cause.
Direct worm removal and global turn actions still run natively.

Before each case the test fixture seeds native RNGs and makes the gameplay
RNG's frame contribution relative to that case, leaving the real frame
counter untouched. This controls seed and timing offsets, but remaining
native state/bodies can still change the number of draws. Run home twice as
a control; new moved/home differences are candidates until their state trace
or native caller identifies the slot-dependent site. No slot fix is included.

The scheduler regression (`lua mods/examples/tools/audit/test_audit.lua`)
validates sequencing against a mock, not WA physics. Live aim, grenade and
cursor assertions still need the first real matches. Headless `/getlog`
playback with a changed engine also needs a newly recorded audit; ordinary
replays do not contain these diagnostic scripts/fixtures.


## Native input messages

| Input | Message | Payload |
|---|---|---|
| fire press / release | `0x26` / `0x27`; active weapon press `0x2C` | none for worm; team id for active weapon |
| left / right / up / down | `0x1E` / `0x1F` / `0x20` / `0x21`; active steering `0x2D` / `0x2E` | none for worm; team id for active steering |
| face left / right | `0x22` / `0x23` | none |
| jump / backflip / special | `0x24` / `0x25` / `0x62` | none |
| Tab | addressed world `0x43` | team id; active worm and native selection mode required |
| fuse | `0x2F` | team, worm index, seconds minus one |
| bounce | `0x31` | team, worm index, 0 minimum / 1 maximum |
| click | `0x32` | team, worm index, packed i16 x/y pixels, facing sign, placement parameter 1 |
| aim | target field | -90..90 degrees, eased by WA's normal aim control |

The table's Space/fire and Enter/jump mappings apply on foot. In native
Jet Pack, Rope, Bungee and Parachute states, Space sends `0x24` to release
the tool and Enter (`key = "jump"`) sends `0x26` through the selected
weapon's normal firing/cursor flow. An activatable released weapon uses
Enter (`0x2C`) while attached. The routing follows state and team control
counts, without inspecting the selected weapon's slot.


## Quick sheep check

Select **Audit sheep** to run Sheep Launcher, Sheep, Super Sheep and Aqua Sheep with the
same Audit map and scheme. It retains the full home weapon table, but runs
four cases instead of 70. This takes roughly half a minute of simulation when
each case settles normally, longer if a missile remains active. The `scope`
option can also be set to `sheep` on the copies profile for a targeted comparison.
Both compared logs must use the same scope and protocol version. Version 2
corrects the active-weapon controls; do not compare it with a version 1 log.

## Quick utilities check

Set `scope = "utilities"` on Audit home (and on Audit copies past 70 for the
matching log) to run only Jet Pack, Low Gravity, Fast Walk, Laser Sight,
Invisibility, Damage ×2, Crate Spy, Double Time and Crate Shower.

The live report from 2026-10-15 exposed a routing error: sending every Space
press directly to the worm fired Bazooka after the sheep launch. Native
TeamEntity input checks its activation/steering counts and broadcasts `0x2C`
with the team id for the next Space press, and `0x2D`/`0x2E` for steering a
flying sheep. `worm:input` now follows that same routing, independent of the
selected fallback weapon or any stock slot. The first press still fires
through the worm; the remote activation has no power-bar release edge.


## Automatic utilities and the scheme

WA automatically consumes stock in utility cells 6..9 (normally Damage x2,
Crate Spy, Double Turn Time and Crate Shower). Infinite ammo there enables
these effects even when the `.wsc` has them off. The original audit profiles
mistakenly did that; the completed version 2 sheep run consequently included
crate drops unrelated to the sheep cases.

Protocol 3 starts those physical cells with zero ammo in every audit profile,
Before each case, the add-on clears their
stock on every team and gives the case's selected weapon infinite ammo. It
clears them again after recording the result. Thus the sheep-only run never
stocks Crate Shower. In the full audit, WA's automatic processing still runs
normally during a test of a weapon placed in one of those cells; that is an
observed slot dependency, not an engine fix or a suppressed result. Effects
already activated by their own case may persist into later cases, as with
other match-wide weapons.

Protocol 4 waits until the first turn is active before validating the roster,
reads it through that round's worm, and requires three worms on each of three
teams. It uses the existing map, with nine separate places on the reserve
strip. Earlier protocols used a different starting roster.

Protocol 5 accepts any starting team and automatically skips to team 1's
first worm before beginning the cases. No restart lottery or forced turn
handover is needed.

Protocol 6 treats Double Damage, Crate Spy, Double Turn Time and Crate Shower
as instant utilities: no equip/fire, one item stocked at frame 40, then the
remaining stock and change in turn clock are sampled. This exercises WA's
normal per-turn automatic activation after stocking; it does not test crate
collision, the crate deck, or the scheme's expedited activation at pickup.
Both these utility IDs and physical automatic-consumption cells start empty
and are cleared between cases. Moved utilities that are not consumed remain
visible as slot dependencies. Native utility effects can persist afterwards.
Compare fresh protocol 6 home/moved logs together.

**Audit followup** runs Bungee, the four instant utilities, then the nine final
fresh-worm cases (14 total). It uses the existing map and three teams of three
worms, and avoids repeating the first 61 cases just to check turn rotation.
Restart WA for the DLL fix: spawned worms now update the native team-arena
count used by ordinary turn rotation, as well as the setup count. No turn
handover was added.

Protocol 7 corrects this Space/Enter routing. The protocol 6 followup attached
Bungee successfully but its supposed Space press fired the fallback Bazooka
and left the worm hanging. The audit now records both attachment and
detachment, and stops before advancing if a case leaves its worm in any of
the four active mobility states. A timeout is not permission to carry that
state into later cases. Compare fresh protocol 7 logs together.

Protocol 8 exercises Select Worm beyond its activation: Space at frame 40,
release at 55, Tab at 90 and 120, then Right at 150 to commit the choice.
Tab at 170 must leave that choice unchanged. The audit follows the team's
currently controlled worm throughout these handovers, rather than treating
the old worm losing control as a completed case. It logs both cycle results,
the confirmation, and the final lock check. Its coverage reports the number
of observed cycles and whether the choice stayed locked. Compare fresh
protocol 8 home/moved logs together.

`worm:input{key = "tab"}` uses WA's native selection handler and its gates;
it does nothing outside selection mode or when called on an inactive worm.
It cannot select a requested worm or give a newly spawned worm a turn.
The existing debug-input/offline/simulation gates still apply.

Protocol 9 adds both Sheep Launcher paths within its one weapon case. The
first launch uses the normal 45-degree aim, starting 128 pixels left of the
station centre. Space at frame 90, while the original rocket remains away
from terrain, releases its sheep; Space at 140 detonates the promoted sheep.
After that body is gone, the worm returns to the station and launches again
with an 85-degree aim, keeping the landing near the platform. The second
Space press waits for an observed replacement sheep body, three near-ground
samples and near-zero vertical speed. There is no third activation on this
landed path, and no extra shot after the sheep disappears. Landed detection
uses the existing missile and terrain APIs; no native contact flag is exposed.
Native missile/burst/explosion traces record the actual result of each input.
The audit stops if the case times out with a surviving launcher sheep.
**Audit sheep** includes this case now; **Audit home/moved** still have 70
weapon cases. Compare fresh protocol 9 logs together.

Protocol 10 sets the turn clock to 60 seconds at the start of every case
(`wa.world.set_turn_clock`). A turn running out part way through a case cut it
short at a different case in every run, handed the turn to another team, and
made Double Time's result depend on the time left. Compare protocol 10 logs
together.

Protocol 11 places the girders in open air. The Girder's click 8 pixels above
the station overlapped the land and WA refused it. Both girder cases now click
above the worm, halfway up the gap between its platform and the one above
(288 pixels above the station). The Girder Starter Pack places five girders,
20 pixels apart and centred on the worm, a click and a fire press every 30
frames. After each one, a `girder` signal says whether there is land at the
click (`placed`). Compare protocol 11 logs together.
