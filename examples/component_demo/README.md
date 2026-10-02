# component_demo

A component bundle (`format_version = 2`): one weapon, one scheme and one
feature. Installing it runs nothing; a profile selects what runs. Pick
"Demo scheme" in the mod loader's Profile tab and tick "Turn note", or put this
in `Mods/wormforge.toml` (the Profile tab writes the same table):

```toml
[profile]
scheme = "demo.scheme"
features = ["demo.turn_note"]

[profile.options."demo.turn_note"]
show = true
```

The scheme's preset places **Big Bazooka** (Bazooka with damage 80) on F1,
and its override sets the weapon's delay to 1; `wkLua.log` shows the merged
data (`round_start -1, delay 1`) and the resolved profile (`profile ...`
lines). The feature adds a HUD line while `show` is on.

The weapon data is written into WA's scheme for the round, whatever scheme
the lobby picked: every team starts with infinite Big Bazookas, usable from
the second round of turns (a scheme delay of 1).
