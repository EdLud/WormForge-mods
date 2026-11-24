# Offline stock weapon audit

This diagnostic fires real WA weapons through `worm:input`, not their Lua
handlers. **Audit home** places all 70 stock weapons at home; **Audit copies
past 70** places a plain copy of each, every one past WA's 70 slots. A
difference between the two is something WA ties to the slot id. Each fired weapon receives infinite ammo at case setup; instant utilities receive one stocked item without a fire input. Delays are zero, crate weights zero,
and their records don't end the turn. Native special weapons may still end it.

Build the diagnostic DLL explicitly:

```sh
bash tools/build-win32.sh --variant diagnostics
python3 tools/install-local.py --variant diagnostics
python3 tools/audit_map.py tmp/input-verb/Audit.png
```

`diagnostics` is disabled by default. Only that build exposes `wa.audit` and
contains the RNG fixture hook. The add-on refuses to run without it. The
fixture requires the bundle's `debug_input = true` and is refused in network
rounds; it and `worm:input` (an ordinary verb in every build) run only inside
simulation callbacks. The engine logs a TEST BUILD banner. An ordinary release has no RNG-control API.

Copy the `tools` bundle to `WormForge/Mods/`, preserving local edits. When
installing by copying files, also copy its `profiles/Audit*.toml` files
into `WormForge/Profiles/`; the profile dropdown reads that folder. In the
WormForge loader, select **Audit home** in the Profile dropdown. The profile
owns the match settings (its `[scheme]`: no mines, oil drums or crates, a
95-second turn; the other settings as in Intermediate), whatever scheme
the lobby shows. Import `Audit.png` from `User/SavedLevels/` into WA's map
editor and select this same saved map for every run. Use three human teams
with three worms each, team 3 reserved for Surrender. Keep the same teams,
map, renderer and settings for every run. The 7680x5376 indexed map has 70
identical flat platforms, 768 pixels between station centres, plus a
reserve platform for waiting worms. Its fixed seed is 20261015.

Restart WA after installing the DLL. Start **Audit home** offline. The add-on
checks the roster and map dimensions/stations on a simulation frame after the
first worm's turn becomes active, moves the waiting worms to the reserve,
and runs automatically. Any team may start: the audit skips ordinary turns
until team 1's first worm receives its turn, then begins the first case.
Keep physical keys released during the test. Save
`wkLua.log` after the HUD shows `Audit complete`; a stopped/error audit isn't
a complete comparison. Then run **Audit copies past 70** on the same map,
with the same teams. Save each log separately.

**Copies past 70.** The `tools` bundle also has a plain copy of each of WA's
weapons (`tools.copy_<name>`, `copy_from` and nothing else). **Audit copies past
70** places the copies alone, each on a slot past WA's 70 as every non-stock weapon
is, and the add-on's `copies` option fires each case's copy
in place of the stock weapon; the stock Skip Go still ends the turns, and the stock Bazooka stays
on slot 1 with infinite ammo, as at home: after a shot WA doesn't re-select, it
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
6000 simulation frames (two minutes).

Hurts on audit worms are logged before returning `"eat"`. Existing hurt API
semantics skip the whole native hurt handler, including its knockback;
this audit doesn't validate the knockback that a cancelled hurt would cause.
Direct worm removal and global turn actions still run natively.

Before each case the test fixture seeds native RNGs and makes the gameplay
RNG's frame contribution relative to that case, leaving the real frame
counter untouched. This controls seed and timing offsets, but remaining
native state/bodies can still change the number of draws. Run home twice as
a control; new moved/home differences are candidates until their state trace
or native caller identifies the slot-dependent site. No slot fix is included.

The scheduler test (`lua mods/examples/tools/audit/test_audit.lua`)
validates sequencing against a mock, not WA physics. Live aim, grenade and
cursor assertions still need the first real matches. Headless `/getlog`
playback with a changed engine also needs a newly recorded audit; ordinary
replays don't contain these diagnostic scripts/fixtures.


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
same Audit map. It keeps the full home weapon table, but runs
four cases instead of 70. This takes roughly half a minute of simulation when
each case settles normally, longer if a missile stays active. The `scope`
option can also be set to `sheep` on the copies profile for a targeted comparison.
Both compared logs must use the same scope and protocol version (currently 11);
compare only logs of the same version.

The Sheep Launcher case runs both of its paths. The first launch uses the
normal 45-degree aim, starting 128 pixels left of the station centre. Space at
frame 90, while the rocket is still away from terrain, releases its sheep;
Space at 140 detonates that sheep. After that body is gone, the worm returns to
the station and launches again with an 85-degree aim, keeping the landing near
the platform. The second Space press waits for a replacement sheep body, three
near-ground samples and near-zero vertical speed. The landed path has no third
activation and no extra shot after the sheep disappears. Landed detection uses
the missile and terrain APIs; no native contact flag is exposed. Native
missile, burst and explosion traces record what each input did. The audit stops
if the case times out with a launcher sheep still alive.

## Quick utilities check

Set `scope = "utilities"` on Audit home (and on Audit copies past 70 for the
matching log) to run only Jet Pack, Low Gravity, Fast Walk, Laser Sight,
Invisibility, Damage ×2, Crate Spy, Double Time and Crate Shower.

Space presses follow the routing of WA's TeamEntity: it checks its activation and
steering counts and broadcasts `0x2C` with the team id for the next Space
press, and `0x2D`/`0x2E` for steering a flying sheep. `worm:input` follows that
routing, whatever fallback weapon is selected and whatever is on the stock
slots. The first press still fires through the worm; the remote activation has
no power-bar release edge.


## Automatic utilities and the scheme

WA automatically uses the stock in utility cells 6..9 (normally Damage x2,
Crate Spy, Double Turn Time and Crate Shower). Infinite ammo there turns these
effects on even when the `.wsc` has them off, so every audit profile starts
those cells with zero ammo. Before each case, the add-on clears their stock on
every team and gives the case's selected weapon infinite ammo. It clears them
again after recording the result, so the sheep-only run never stocks Crate
Shower. In the full audit, WA's automatic processing still runs normally while
a weapon placed in one of those cells is tested; that is an observed slot
dependency, not an engine fix or a hidden result. Effects already activated by
their own case may last into later cases, as with other match-wide weapons.

The audit waits until the first turn is active before checking the roster,
reads it through that round's worm, and requires three worms on each of three
teams. It uses the existing map, with nine separate places on the reserve
strip. Any team may start: the audit skips to team 1's first worm before the
first case, with no restart or forced turn handover.

Damage ×2, Crate Spy, Double Turn Time and Crate Shower run as instant
utilities: no equip or fire, one item stocked at frame 40, then the remaining
stock and the change in turn clock are sampled. This exercises WA's normal
per-turn automatic activation after stocking; it doesn't test crate collision,
the crate deck, or the scheme's expedited activation at pickup. Both these
utility IDs and the automatic-use cells start empty and are cleared between
cases. Moved utilities that aren't used stay visible as slot dependencies.
Native utility effects can last afterwards.

Every case starts with the turn clock at 60 seconds
(`wa.world.set_turn_clock`), so a turn never runs out part way through a case,
and Double Time's result doesn't depend on the time left.

## Audit followup

**Audit followup** runs Bungee, the four instant utilities, then the nine final
fresh-worm cases (14 total). It uses the existing map and three teams of three
worms, and checks turn rotation without repeating the first 61 cases. Spawned
worms update WA's team-arena count used by ordinary turn rotation, as well as
the setup count; the audit adds no turn handover.

The audit records both the Bungee's attachment and its detachment, and stops
before going on if a case leaves its worm in any of the four active mobility
states. A timeout doesn't carry that state into later cases.

Select Worm is tested beyond its activation: Space at frame 40, release at 55,
Tab at 90 and 120, then Right at 150 to commit the choice. Tab at 170 must
leave that choice unchanged. The audit follows the worm the team controls
through these handovers, rather than treating the old worm losing control as
a completed case. It logs both cycle results, the confirmation and the final
lock check; its coverage reports the number of cycles seen and whether the
choice stayed locked.

`worm:input{key = "tab"}` uses WA's native selection handler and its gates;
it does nothing outside selection mode or when called on an inactive worm.
It can't select a requested worm or give a newly spawned worm a turn.
It runs only from simulation callbacks.

## Girders

Both girder cases click in open air above the worm, halfway up the gap between
its platform and the one above (288 pixels above the station). The Girder
Starter Pack places five girders, 20 pixels apart and centred on the worm, with
a click and a fire press every 30 frames. After each one, a `girder` signal
reports whether there is land at the click (`placed`).
