# Gravler Strike example

This bundle's one weapon, Gravler Strike, builds on WA's Mole Squadron
wherever a profile places it (by default where the Concrete Donkey sits). It
copies the Mole Squadron's fire path, so WA owns the strike cursor, falling moles, digging,
damage, sound and turn timing. PX's `weapon_gravler.pxl` defines Gravler Strike
in weapon data and uses its script only to replace the mole's four digging
sprite sheets (IDs 245–248). The four PNG strips here were extracted without
modification from that local PX library. The pack applies the same global
sprite overrides by name: `moledive` and `moledig1`–`moledig3` resolve to IDs
158–161 in WA 3.8.1. PX weapon-data tuning still needs in-game comparison against
WA's Mole Squadron parameters. The panel icon is WA's Mole Squadron icon for
now; the PX Gravler Strike icon is not yet wired into the panel.

Copy the directory into `Worms Armageddon/Mods/` and place the weapon in a
profile; online, the host's profile and bundles reach every peer. The strike
uses WA's stock mole terrain cuts rather than calling `wa.land.cut` from Lua.
