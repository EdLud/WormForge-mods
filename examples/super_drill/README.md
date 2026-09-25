# Super Drill example

This pack replaces the Pneumatic Drill slot with a PX-style Super Drill. WA
still runs the normal drill: it moves the worm, consumes ammo, plays its sound
and animation, and makes its randomized cuts. An invisible watcher adds a
second cut with WA's drill mask at the worm's current position each frame while
the worm is drilling. It despawns when that state ends.

Copy this directory into `Worms Armageddon/mods/` on every network peer. Do not
load it alongside another pack that replaces `pneumatic_drill`. The pack is an
API example and a terrain-sync test based on PX's packaged Super Drill script.
Before shipping it in a network game, verify a recorded round and a two-peer
match with matching wkLua builds and packs.
