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

## +N Seconds

An instant utility that adds configurable time. Its stable ID remains
`utilities.plus_ten`, so existing profiles keep their weapon and ammo settings.

| Option | Values | Default |
|---|---|---|
| Seconds added (`seconds`) | 1–500 | 10 |
| Time bonus mode (`bonus_mode`) | `stack`, `once_keep`, `once_discard` | `once_keep` |
| On collect during retreat (`retreat_collect`) | `activate`, `keep`, `nothing` | `keep` |

With **Auto-Use on**, pickups activate immediately during normal turn time.
`stack` gives a bonus for every activated unit and activates finite inventory
at turn start. Infinite inventory uses one unit at turn start, plus each newly
collected unit, without becoming finite. `once_keep` permits one bonus per turn
and keeps extra pickups for later. `once_discard` permits one bonus per turn
and discards surplus from that pickup and all later pickups during normal turn
time. Previously held inventory and infinite ammo are preserved; turn start
consumes just one held unit in either once mode.

During retreat, `activate` extends the retreat countdown; `keep` saves the
pickup for the next turn; `nothing` discards only the pickup. These choices
apply only with Auto-Use on. **Auto-Use off** always keeps pickups in inventory,
including during retreat, for manual use. The retreat collection setting takes
precedence over the bonus mode: `keep` banks the whole pickup even in
`once_discard`; `activate` follows the selected bonus mode. Manual use obeys
the per-turn limit too; a second use in either once mode refunds the unit.
Using this utility does not end the turn. Each countdown is capped at one hour.

```toml
[weapons]
"utilities.plus_ten" = { row = "utility", column = 6 }

[weapon_settings]
"utilities.plus_ten" = { crate = 60, on_collect = "use" }

[options."utilities.plus_ten"]
seconds = 15
bonus_mode = "stack"
retreat_collect = "keep"
```

The Lua lives in `weapons/plus_n.lua`; the icon is `sprites/plus_n.png`.
Run `lua mods/examples/utilities/test_auto_use.lua` to check these rules.

A weapon's ammo, infinite included, is a weapon setting (the Weapons tab), not
a utility. The switches are those mods' own code, in `features/`, loaded only
when switched on.

Everything runs in simulation callbacks (`wa.on.turn_start`, and
`wa.on.worm_message` for the wind), so the settings are the same on every peer
and in replays: the selection, options included, is frozen with the bundles.

WA rolls a turn's wind after it starts the turn, so the wind is set at the
first frame after `turn_start` rather than in it.
