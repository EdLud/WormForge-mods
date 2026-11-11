# Project X Curse of Death

Four weapons from Project X's `utility_curse_of_death.pxl`
(`utility_curse_of_death/scripts/curse_of_death_script.txt`):

- **Death Mark** / **Marked For Death** mark a worm: it takes the mark's
  percentage of every blast and hit for four team turns.
- **Homing Curse** / **Wish Of Death** curse a worm: loose mines, missiles, oil
  drums and arrows lock onto it and home for three team turns, or until two
  objects have locked.

The two click weapons refund the shot with "Nothing found!" when the click
finds nobody.

## Options

| Option | Default | Meaning |
|---|---|---|
| `dmg_percent` | 150 | Mark damage, percent (110-500). Stored per marked worm. |
| `max_homing` | 3 | Objects that may lock onto one cursed worm (1-50). |

The numbers are stored per worm, so two placed weapons keep their own.

## Departures

- The homing pass steers mines, missiles, oil drums and arrows natively
  (`wa.on.missile_frame`, `wa.on.body_move`), as PX's `ChaseTargetCurse` does.
  A Lua actor that moves itself (the Bowling Ball, both Bunker Busters) cannot
  be steered that way; the curse instead registers an attract `wa.magnetism`
  field at the cursed worm (the Cursor's 300 px magnet). Magnetic actors are
  pulled by their own movement code through the engine's shared field service;
  `native = false` keeps the field off the native objects the pass already
  steers.
- PX's 5-slot `beingTargetedBy` array is replaced by a per-object `ever` table
  and a per-worm lock count, which is what PX's checks mean.
