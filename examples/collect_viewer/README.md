# Collect Viewer

Enable alongside stock weapons or Highlander. Every acquired copy floats from
its crate's pickup position or the killed worm's position for Highlander rewards,
independently of later worm movement. Every weapon uses its panel symbol. Black
and near-black pixels (all RGB channels at most 24/255) in those popup symbols
are transparent; the original panel artwork is untouched. It creates no
physics bodies.

Diagnostics are enabled by `CONFIG.debug`: the log records grants, preview
selection, visibility decisions and expiration without logging every draw.

Edit `CONFIG` in `viewer.lua` to tune the default 24px bounding size, 48px rise,
6px sine amplitude, copy spacing, two-second lifetime or 1.5-second fade.
Each copy follows one sine cycle, with fixed phase offsets and no randomness.
Size preserves aspect ratio; art is a static frame. Time is 100 simulation
frames (50 FPS), so pause pauses the effect. Icons stay opaque for 500ms,
then fade linearly to transparent over 1500ms. `lifetime - fade` controls
the opaque hold; `fade = 0` disables fading. Simultaneous copies have separate
grid positions.

Only the coalition active when the grant happened sees it: online, its local
player and allies, never opposing players or spectators. Offline hotseat hides
an old effect when a different coalition starts its turn. Coalition means team
colour, independent of ammo bookkeeping. Rendering requires WA's D3D9 shader
renderer, as the other `wa.draw` packs do.

Crates and virtual inventory acquisitions/transfers report grants automatically.
Initial deals, inventory apply, turn refills, refunds and removals are silent.
`inventory:transfer(from, to, {x = ..., y = ...})` can supply a captured acquisition
position in 16.16 coordinates; otherwise it defaults to the receiving worm.
Highlander supplies the victim's position without changing the recipient or coalition.
A script granting directly through `worm:ammo` can report it afterwards:

```lua
worm:ammo("grenade", 2)
wa.weapons.notify_grant({
  worm = worm,
  items = {{ weapon = "grenade", amount = 2 }},
})
```

`notify_grant` never changes ammo. It snapshots the recipient's position unless
`x` and `y` (16.16) are supplied; only call it from a simulation callback.
`wa.on.weapon_grant(fn)` receives `worm_id`, `items`, `x`, `y`, `alliance`,
`frame` and `source` (`crate`, `inventory`, `script`). Delivery waits until the
stock simulation frame has finished; no live worm handle is retained.

`wa.weapons.visual("grenade")` returns `{sprite, frame, width, height, kind}`,
where `kind` is `icon`, or nil when its art is unavailable. Stock symbols and
pack panel icons are copied into the shared GPU atlas with black and near-black
pixels made transparent (RGB threshold 24/255). No extra WA sprite slots or
icon ownership is involved.
`wa.world.frame()` returns the simulation frame or nil outside a match.
`wa.world.is_local_alliance(colour)` is only legal in draw/HUD callbacks and
returns whether this display belongs to that coalition (including hotseat).

Stock crate collection and black transparency have been confirmed in game.
Automated tests cover grants, visibility, icon selection and trajectories;
network and replay playtesting remain required.
