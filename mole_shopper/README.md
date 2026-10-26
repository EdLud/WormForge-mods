# Mole Shopper

Ported from `FOW - Mole Shopper - popka+0rang3.pxs` in Orange's
28 September 2026 Project X build. This bundle adds the scheme's missing
components; its full profile also reuses existing PX ports.

Its test profiles (unlimited ammo and time, for checking components rather
than the finished scheme) live in the repository's `tests/mole_shopper/fixtures/`
and don't ship with the pack.

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

Vision uses the existing WormForge fog renderer: a 110px worm circle,
coalition ownership and terrain shadows, without map memory. The full profile
has no aiming cone; the focused lights test retains the original 700px cone.
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

The fourth test profile checks **Antifire Suit**: native flames cannot damage
or knock the wearer, and nearby non-melting flames are repelled. Protection
survives other teams' turns and ends when the wearer's team next gets a turn.
The shield stays faintly visible and flashes red when it blocks a flame hit;
it follows the wearer's Invisibility presentation.

**FOW Mole Shopper** is the full scheme profile: 58 selectable weapons, 199 HP,
40-second turns and coalition fog. Its starting inventory, panel layout,
weapon handling, crate counts/types/chances and per-weapon cave restrictions
come from the PX records. Turn options and initial delays use the attached
WA scheme, with PX's header flags taking precedence. WA scheme power tweaks
are disabled in the source; its native weapon tuning is kept in per-profile
named record overrides. The original utilities category weight is zero.

Exp. Rain remains Precipitator's internal payload. j-bomb and i-bomb retain
the neutral names/artwork. Shift-assisted faster aiming is deferred. The
reused ports retain their existing rendering/physics adaptations; this is
not a replacement for the PX engine. The four small test profiles remain
available for focused checks.
