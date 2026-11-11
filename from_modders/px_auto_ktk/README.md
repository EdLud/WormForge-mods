# Auto Kill the King

Project X's Kill the King with the king placed by the mod instead of by a
hand-made map.

One king. The attackers must destroy its terrain before the attack timer runs
out; the defenders win otherwise.

## Where the king goes

The map is cut into fifths. The king goes around the middle of the defenders'
edge fifth (`side = left` by default), found in this order:

1. **Natural cave** — the column is measured with two traces: one down from the
   top for the roof's outer face, one up from the map bottom for the ground's
   underside. A cave needs a floor and **150 px of roof** over it, enough air for
   the king plus a worm's height, and dry ground (above the water line).
2. **Dug cave** — with no cave, a hall is cut under 150 px of roof, with
   `CAVE_HEADROOM` above the king, and a zig-zag exit is dug from the hall's edge
   to the surface. The exit is offset from the king so the roof over the king
   stays whole.
3. **Mirrored edge** — if the fifth is too thin to hold a cave, steps 1–2 run on
   the other edge.
4. **Open ground** — a flat map with nothing to dig gets the king on the
   surface of the mirrored edge.

The king is PX's terrain stamp (`leftsmallking`/`rightsmallking`, 25x40 px of
art in a 20x40 win box; `king_size = big` uses the 40x80 pair). Its solid pixels
are the win condition, counted every 5 frames.

## Worm spawn points

With `move_worms = true` (default), on the first frame:

- Defenders are warped onto their king: one row just above its head, spread
  across the cave's free span (or the king's own width in the open).
- Attackers are warped onto the surface of the mirrored fifth, facing the king.

## Options

| key | default | |
| --- | --- | --- |
| `side` | `left` | `right`, or `random` (rolled once per round) |
| `king_size` | `small` | `small` (20x40) or `big` (40x80) |
| `allow_carve` | `true` | dig a cave when no natural one is found |
| `move_worms` | `true` | teleport both teams to the edges |
| `attackers_team` / `defenders_team` | `red` / `blue` | WA team colours |
| `attack_time_seconds` | `300` | attack timer |
| `timer_mode` | `attack_only` | or `defend_and_compensate` |
| `defender_gain_ms` | `5` | refunded per defender frame in that mode |
| `destruction_percent` | `70` | terrain share destroyed to win |
| `show_timer` / `show_king_hp` | `true` | HUD lines |

## Differences from `px.ports`' `ktk.control`

- `ktk.control` takes the king box from `king1_x`/`king1_y` options; AutoKTK
  finds the ground itself and stamps PX's king art there.
- AutoKTK is one king only, and it moves the worms.
- The edge object cleaner is not duplicated here; enable `ktk.control`'s rules
  or the `px.ports` cleaner for that. Do not run both KTK components at once.
