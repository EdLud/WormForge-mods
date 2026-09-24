# Gravler Strike example

This pack places Gravler Strike in the Concrete Donkey slot. It copies WA's
Mole Squadron fire path, so WA owns the strike cursor, falling moles, digging,
damage, sound and turn timing. PX's `weapon_gravler.pxl` defines Gravler Strike
in weapon data and uses its script only to replace the mole's four digging
sprite sheets (IDs 245–248). This first gameplay port uses WA's stock mole
graphics and Mole Squadron parameters; the PX sprite replacement and any
weapon-data tuning still need a separate visual and in-game comparison.

Copy the directory into `Worms Armageddon/mods/` on every network peer. It
claims `donkey`; disable other packs that claim that slot. This pack builds on
the terrain work in the `digging` branch, although the strike itself uses WA's
stock mole terrain cuts rather than calling `wa.land.cut` from Lua.
