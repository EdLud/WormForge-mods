# component_demo

A component bundle (`format_version = 2`): one weapon, one scheme and one
feature. Installing it runs nothing; a profile selects what runs. Put this in
`Mods/wormforge.toml`:

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
lines). The feature adds a HUD line while `show` is on. Weapon data such as
ammo and delay is checked and handed to the weapon, not yet written into WA's
scheme.
