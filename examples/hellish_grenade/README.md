# Hellish Hand-Grenade

Project X's Hellish Hand-Grenade on the Holy Hand Grenade's slot: PX's panel
icon, the worm holding and taking out the horned grenade on flat ground and
slopes, and the thrown grenade spinning in flight.

How it fires: `copy_from = "holy_grenade"` plus a named `patch` for the
fields PX's hellish weapon changed (web editor style). Against the stock
Holy Hand Grenade, the Hellish one:

- has a weaker blast: 70 damage and 80 power instead of 100 and 100;
- bursts into fire on detonation, as the Petrol Bomb does;
- plays two of the team's voice lines instead of the Hallelujah and its
  bounce sound (sound ids above 126 are the speech bank, so the line depends
  on the team's voice);
- sets a 3 s retreat time.

It keeps the Holy Grenade's fixed 3 s fuse, bounce, gravity and spin.

Do not enable it alongside another pack that replaces `holy_grenade`, such as
the `panel_icon` example: the first pack loaded keeps the slot.

## Sprite slots

The thrown grenade is a WA sprite and uses one of the 223 shared slots. The
worm sheets are drawn by the GPU renderer and use none.
