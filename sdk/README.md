# WormForge shared helpers

Declare the dependency in your bundle's `mod.toml`:

```toml
dependencies = ["wf.sdk"]
```

Then import the public helper:

```lua
local sprites = require("wf-lib/px_sprite_builder")
```

`sprites.PX_POSTURE` and `sprites.PX_HANDS` name the library's artwork.
Use them in `worm_sprites` and `hold.hand`; your weapon's sheet remains relative
to your own mod. `sprites.flight(ctx, { weapon = ctx.id, sheet = "sprites/my.png",
anim = "track" })` draws a turning actor over your native missile. Register
your sheet through `wa.weapons.replace`'s `sprites` field first.

The helper also exposes `cyclical_frame`, `track_angle`, `rotation_turn` and
`spin_turn`, preserving the PX port's existing calculations.

`require("wf-lib/holds")` returns the posture/hand data directly.
`require("wf-lib/shared")` returns `{ sprites = ..., holds = ... }`.
`require("wf-lib/parkour").new()` returns a movement callback
for `wa.on.worm_message` (frame finish, jump and jump-up). It implements the
shared wall-jump/bunny-hop movement and cooldowns; the caller chooses when it
is active. The Utilities global option and PX inventory utility both use it.
`air_input(worm, msg)` identifies its airborne jump inputs. Controllers share
Parkour cooldowns and deduplicate inputs/frames within the match, so enabling
both forms cannot apply a movement input twice.

`require("wf-lib/own_time")` counts a worm's own frames under `worm.time_scale`
(Bullet Time's). A `FRAME_FINISH` hook runs once a world frame: what it does
once a frame of the worm's (a push, a damping, a timer) it repeats
`own_time.frames(worm)` times, an integer with the fraction carried, and a
speed it hands the worm from something on the world's time it divides by
`own_time.scale(worm)`. Both are 1 for a worm at the world's pace.

These are public helpers, separate from Highlander's internal match state.
Module tables and private globals are separate for each consuming bundle.

`require("wf-lib/tooltip")` is the weapon tooltip: one window in WA's medium font
at the bottom right, over the wind bar, bordered in the active team's colour
and seen by that team's coalition. WormForge fades it out while WA's weapon
panel is open.

```lua
local tooltip = require("wf-lib/tooltip")
-- While the turn's worm holds the weapon, every frame: its settings, or nil.
tooltip.hint("my.weapon", function(worm) return "My Weapon: " .. mode .. "\n+ next mode" end)
-- Something that just happened, for three seconds (or `seconds`) of the turn.
tooltip.notice(worm, "No space to launch!")
```

`\n` breaks lines. Run both from simulation callbacks. With an engine older
than `wa.hud.window`, the text goes to WA's top banner instead, on one line.

Every selected bundle's dependency closure is frozen for online games and
replays. Replay imports use the recorded files rather than the installed SDK.
Relative imports inside a library resolve within that library. A consumer can
import only names explicitly exported by its declared dependencies.

Library authors declare `[exports]` as public name to local Lua entry mappings.
An optional `asset_namespace = "wf-lib/name"` exposes library-owned assets to
dependents with qualified paths such as `wf-lib/name/sprites/hand.png`. Sprite
settings come from the library manifest. Paths stay inside the named provider.

Make your own mod directly under `WormForge/Mods/`; `Mods/wf-lib/` belongs to
the catalogue's installs.

`require("wf-lib/lightning")` is Project X's Lightning Strike. Declare
`lightning.SPRITES` and `lightning.SOUNDS` (a weapon's `sprites` and `sounds`,
or `wa.assets.load`), call `lightning.setup()` once to draw your strikes, then
from a simulation callback:

```lua
lightning.strike{ x = 300, y = 200, side = 1, owner = worm, effects = true }
```

The bolt comes down to (x, y) at 30 degrees, from the left with `side` 1 and
from the right with -1. It gives a 150-frame warning, then strikes: it heals
worms on its line by 25, revives graves at `revive_health` (10), starts mines
and hits crates and oil drums. With `effects = false` it only lights up and
thunders. `owner` is a worm or `"none"`; the thunder plays at `thunder_on`,
else where the bolt lands.

`lightning.extend{ beam, before_hit, heals, revived, after_hit }` adds what
your own objects need: `beam(sx, sy, dx, dy, ex, ey, hit)` returns where the
beam stops instead, `heals(worm)` returning false spares a worm, `revived(worm)`
hears a revive, and `after_hit(s, struck)` gets a test for what is on the line.
Each mod that imports it has its own strikes and hooks.

`lightning.gfx().draw_cloud(puffs, x, y, power, reach, spread, style)` draws
the storm cloud lit by a light at (x, y) (draw callbacks). Each puff has `x`,
`y`, `size` and `alpha`; `style` sets `depth`, `dark = { r, g, b }` and
`alpha`. `lightning.flash(s)` is a strike's brightness, 0 to 1.
