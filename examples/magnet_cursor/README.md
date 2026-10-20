# Magnet Cursor

Requires the DLL with `wa.magnetism`. The supplied **Magnet Cursor** profile
also requires the PX pack for its Bunker Busters and Bowling Ball Strike.
The cursor component itself has no PX dependency and can be added to any profile.

Select **Magnet Cursor** with F8 and move the mouse. Like Cursor Light, this
uses WA's land cursor while the worm holds the teleporter. Within a 300 px
range the cursor attracts native mines/missiles and actors that participate
in the shared magnetic field. Terrain does not block magnetic force.

- **1–9:** set strength to 1×–9×. Both the falloff coefficient and force cap
  scale with the level; range remains 300 px. Default: 1×.
- **+:** switch between attraction and repulsion. Default: attraction.
- **Click:** keep the cursor active, without teleporting, spending ammo or
  ending the turn.
- **Switch weapons, die or end the turn:** remove the cursor and its field.

The HUD shows the current level and polarity. Strength and polarity persist
across reselecting and turn changes. Only synchronized input changes them;
holding a digit sets a level, and holding + toggles once per press.

The profile includes mines (F5) and PX's Bunker Busters and Bowling Ball Strike
(F6), configured to continue after use so you can switch to the cursor to
test them. Skip Go (F12) is included for turn transitions. A Bunker Buster's
drilling steering still has PX's own force cap, even at high cursor strengths.

The demo uses only Lua and the shared [magnetism API](../../../docs/magnetism.md).
It does not enumerate targets or import another weapon's code. Multiple
fields combine in the engine; actors used for artwork and bookkeeping keep
their default zero response.

Run its lifecycle/control harness from this folder with `lua test_weapon.lua`.
