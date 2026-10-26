# Mole Shopper

Work in progress from `FOW - Mole Shopper - popka+0rang3.pxs` in Orange's
28 September 2026 Project X build. This bundle adds the scheme's missing
components; the completed profile will also reuse existing PX ports.

The first test profile contains Lantern, Far Sight and launched Mole Bombs;
the second contains j-bomb, i-bomb, Power Shotgun and Thrown Ming Vase.
Both have unlimited ammo/time for checking these components, rather than the
finished scheme's inventory or crate distribution.

- **Lantern:** throw a persistent physical light, visible to its coalition.
  It uses native mine movement without a mine's fuse or trigger, and drowns.
- **Far Sight:** click to place a stationary coalition light for the round.
  Terrain blocking rejects solid-terrain clicks without spending ammo and casts
  terrain shadows. Disable it to place and reveal through terrain.
  The PX controller's 60-frame timer does not limit the reveal's lifetime.
- **Mole Bombs:** launch two stock moles per use at fixed 20% power, without charging.
  Space switches to digging;
  Shift accelerates only this component's digging child. Highlander's placed
  Mole Bomb and the stock Mole Bomb remain unchanged.

Vision uses the existing WormForge fog renderer: a 110px worm circle, a 700px
aiming cone, coalition ownership and terrain shadows, without map memory.
Lanterns reveal 110px and Far Sight 155px. PX's soft light falloff is adapted
to this renderer; simulation never consults local visibility.

Original Lantern/Far Sight art and reveal audio remain weapon-scoped.
Neutral **j-bomb** (black dynamite, amber glow) and **i-bomb** (black grenade,
cyan glow) retain their source gameplay, without themed speech or music.
Their new art is generated, then sized for WA's panel and native projectile
animation. Power Shotgun and Thrown Ming Vase use their original PX art.

A third test profile adds Golden Grenade and Precipitator. Golden Grenade has
a wide linear blast and four explosive secondary grenades. Precipitator keeps
native 25-shot gun timing while launching clouds and falling stones. Both need
this branch's updated DLL.

Antifire Suit, Shift-assisted aiming, final
inventory/crate tuning and a complete playable scheme remain subsequent work.
