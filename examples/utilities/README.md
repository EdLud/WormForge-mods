# Core utilities

A features bundle (`core.utilities`, `format_version = 2`): one feature,
**Utilities**, with the match settings the lobby scheme doesn't have and some
players' favourite mods as switches. It changes nothing until a profile
selects it: tick "Utilities" on the mod loader's Profile tab and set it up
below the list, or write it by hand in a profile file in `WormForge/Profiles`:

```toml
features = ["core.utilities"]

[options."core.utilities"]
heal_per_turn = 10
live_hp = true
```

| Setting | Type | What it does |
|---|---|---|
| Heal at turn start | number, 0–50 | Health the worm whose turn starts gets. |
| ExTurnSide | switch | Left and right turn the worm during rope swings and other actions. By red. |
| Agility | switch | The arrow keys steer the worm a little in the air. By Zed and 0rang3, ported by red. |
| Live HP | switch | Non-active worms' health bars follow damage immediately, down to zero, preserving freeze and momentum. Originally by reddaz. |
| Instant Death | switch, off by default | Zero-HP non-active worms start their native death sequence once their own motion settles, without waiting for the rest of the battlefield. |
| Collect viewer | switch | What a crate gave pops up over it, for the team that took it. |

Gravity and wind belong to the profile's **Scheme** tab (`[scheme]`),
including `gravity`, `constant_wind` and `wind`.

Live HP requires a DLL providing `worm:commit_health()`. It commits actual
damage through WA's health-label handler, including for 1 HP survivors
and zero-HP worms awaiting their death animation,
without synthetic hits, healing pulses or changing the worm's state. Ice
Arrow can freeze its victim normally. Active worms retain WA's ordinary
health timing; death timing stays with WA for every worm. Nothing forces
worms to die in mid-flight.
Run its regression harness from the repository root with
`lua mods/examples/utilities/test_live_hp.lua`.

Instant Death is independent of Live HP. Enable `instant_death = true` in
the same Utilities options table, or use the **Instant Death** switch in
the loader. It requires `worm:allow_death()` in the DLL. WA still owns each
worm's movement and landing, then its normal death animation, explosion and
grave. The active worm keeps its ordinary turn/death rules. Falls and direct
HP changes are covered by the next simulation frame too. Run
`lua mods/examples/utilities/test_instant_death.lua` from the repository root
to check both switches independently and together.

## +10 Seconds

A weapon (`utilities.plus_ten`): an instant utility of our own, in place of
Double Time. It adds ten seconds to the turn going on, through
`wa.world.set_turn_clock`, and comes in utility crates (`crate.type`, a
40% weight by default). With **Auto-Use=true** (`on_collect = "use"`, the
default), it spends one at turn start or on pickup if unused this turn,
keeping extra copies for later turns. Infinite ammo remains infinite.
**Auto-Use=false** (`on_collect = "keep"`) stocks every pickup for manual
use. Firing adds ten seconds without ending the turn. Place it on a profile's
panel and set it on the Weapons tab like any weapon:

```toml
[weapons]
"utilities.plus_ten" = { row = "utility", column = 6 }

[weapon_settings]
"utilities.plus_ten" = { crate = 60, on_collect = "keep" }
```

A weapon's ammo, infinite included, is a weapon setting (the Weapons tab), not
a utility. The switches are those mods' own code, in `features/`, loaded only
when switched on.

Everything runs in simulation callbacks (`wa.on.turn_start`, and
`wa.on.worm_message` for the wind), so the settings are the same on every peer
and in replays: the selection, options included, is frozen with the bundles.

WA rolls a turn's wind after it starts the turn, so the wind is set at the
first frame after `turn_start` rather than in it.
