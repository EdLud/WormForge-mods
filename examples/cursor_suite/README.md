# Cursor Suite

One **Cursor** weapon (`cursors.cursor`), with infinite ammo and no turn end
or teleport on click. Select it, then press **+** (top row or keypad) to cycle:

| Mode | Action |
|---|---|
| Light | Cast a 300 px terrain-blocked light, visible to its owner; requires fog for the lighting effect |
| Magnet attract | Attract magnetic objects within 300 px at fixed strength |
| Magnet repel | Repel magnetic objects within 300 px at fixed strength |
| Revive | Click near a linked gravestone to revive its original worm with 100 HP |
| Freeze | Click near a living worm to apply WA's native freeze |
| Fire | Hold the left mouse button to spray rainbow petrol flames at 25 flames/second |

The HUD names the current mode. Holding + advances once; release and press
again to advance another mode. Each worm starts in Light and remembers its
own mode across selections and turns. Number keys do not change magnet power.
Switching modes removes the previous light or magnetic field immediately.
Switching weapons, dying or ending the turn removes the cursor and its effect;
a remembered selection restores it next turn.

Revive and Freeze choose the nearest eligible target within 24 px. Revive
leaves unlinked graves and any revival WA refuses alone. Freeze can target
either team, including the caster. WA owns revival placement, turn effects
and freeze/thaw behavior.

Fire uses WA's fire physics and damage. Its rainbow petrol flames do not
spread into untinted fires, but still burn worms. On selection or entering
Fire mode, it waits 60 ms (three simulation frames, rounding up 50 ms) and
requires releasing any held click before a new press can spray. Leaving Fire
mode stops emission; existing flames burn out naturally. The rainbow tint
requires WA's D3D9 shader renderer. Simulation callbacks own mode changes
and actions; HUD drawing only reads the applied mode.

The **0.9.3 demo profile** places Cursor and PX's Bowling Ball Strike, with
fog, Live HP and Instant Death enabled. Select Cursor and press + to try the
other modes. The demo needs the Fog of war, Utilities and Project X ports
bundles; Cursor Suite itself has no PX dependency.

This replaces the five separate cursor weapon components. Existing saved
profiles are kept unchanged: replace their old cursor entries with
`cursors.cursor` in the loader, or select **0.9.3 demo profile**. The old
individual Cursor profiles are no longer bundled. The standalone Cursor
Light and Magnet Cursor bundle folders must remain removed when using this
bundle.

Run from this folder:

```sh
lua test_cursor.lua
```
