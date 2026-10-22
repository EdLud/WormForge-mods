# WormForge shared helpers

Declare the dependency in your bundle's `mod.toml`:

```toml
dependencies = ["wf.sdk"]
```

Then import the public helper:

```lua
local sprites = require("wf-lib/px_sprite_builder")
```

`sprites.PX_POSTURE` and `sprites.PX_HANDS` name the library's own artwork.
Use them in `worm_sprites` and `hold.hand`; your weapon's sheet remains relative
to your own mod. `sprites.flight(ctx, { weapon = ctx.id, sheet = "sprites/my.png",
anim = "track" })` draws a turning actor over your native missile. Register
your sheet through `wa.weapons.replace`'s `sprites` field first.

The helper also exposes `cyclical_frame`, `track_angle`, `rotation_turn` and
`spin_turn`, preserving the PX port's existing calculations. See
`examples/shared_library_demo` in the source repository for a complete weapon.

`require("wf-lib/holds")` returns the posture/hand data directly.
`require("wf-lib/shared")` returns `{ sprites = ..., holds = ... }`.
These are public helpers, separate from Highlander's internal match state.
Module tables and private globals are separate for each consuming bundle.

Every selected bundle's dependency closure is frozen for online games and
replays. Replay imports use the recorded files rather than the installed SDK.
Relative imports inside a library resolve within that library. A consumer can
import only names explicitly exported by its declared dependencies.

Library authors declare `[exports]` as public name to local Lua entry mappings.
An optional `asset_namespace = "wf-lib/name"` exposes library-owned assets to
dependents with qualified paths such as `wf-lib/name/sprites/hand.png`. Sprite
settings come from the library manifest. Paths stay inside the named provider.

Create your own pack directly under `WormForge/Mods/`. `Mods/wf-lib/` belongs to
catalogue installations. Local edits are protected from Update All. Explicit
replacement keeps the previous complete folder in `WormForge/Backups/Packs/`;
file baselines live separately in `WormForge/Installed/`. Saved profiles remain
in `WormForge/Profiles/`.
