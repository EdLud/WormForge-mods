# utilities

A features bundle (`format_version = 2`): one feature, **Utilities**, with
settings of all three option types. It changes nothing until a profile selects
it: tick "Utilities" in the mod loader's Profile tab and set it up below the
lists, or write the table by hand in `Mods/wormforge.toml`:

```toml
[profile]
features = ["core.utilities"]

[profile.options."core.utilities"]
gravity_pct = 60
wind = "none"
heal_per_turn = 10
infinite_ninja_rope = true
```

| Setting | Type | What it does |
|---|---|---|
| Gravity % | number, 25–200 | Scales the lobby scheme's gravity from the first turn on. Low Gravity still halves it. |
| Wind | choice | `scheme` leaves WA's wind alone; `calm` halves each turn's wind; `none` stills it. |
| Heal at turn start | number, 0–50 | Health the worm whose turn starts gets. |
| Infinite Jet Pack / Parachute / Ninja Rope | checkboxes | The team whose turn starts has unlimited ammo of it, with no delay. |

Everything runs in simulation callbacks (`wa.on.turn_start`, and
`wa.on.worm_message` for the wind), so the settings are the same on every peer
and in replays: the selection, options included, is frozen with the packs.

WA rolls a turn's wind after it starts the turn, so the wind is set at the
first frame after `turn_start` rather than in it.
