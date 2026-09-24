# Gravler Strike example

This pack places Gravler Strike in the Concrete Donkey slot. It copies WA's
Mole Squadron fire path, so WA owns the strike cursor, falling moles, digging,
damage, sound and turn timing. PX's `weapon_gravler.pxl` defines Gravler Strike
in weapon data and uses its script only to replace the mole's four digging
sprite sheets (IDs 245–248). The four PNG strips here were extracted without
modification from that local PX library. The pack applies the same global
sprite overrides by name: `moledive` and `moledig1`–`moledig3` resolve to IDs
158–161 in WA 3.8.1. PX weapon-data tuning still needs in-game comparison against
WA's Mole Squadron parameters. The panel icon is WA's Mole Squadron icon for
now; the PX Gravler Strike icon is not yet wired into the panel.

Copy the directory into `Worms Armageddon/mods/` on every network peer. It
claims `donkey`; disable other packs that claim that slot. This pack builds on
the terrain work in the `digging` branch, although the strike itself uses WA's
stock mole terrain cuts rather than calling `wa.land.cut` from Lua.
