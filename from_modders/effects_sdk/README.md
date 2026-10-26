# Project X Effects SDK

Shared effect helpers for the Project X ports. This is a library bundle: it
declares no components, so it never takes a panel slot. A weapon bundle pulls
it in when it needs one of the exports.

```toml
dependencies = ["effects.sdk"]
```

```lua
local trail = require("wf-lib/effects/trail")
local fx = require("wf-lib/effects/px_effects")

trail.install()
fx.install({ trail = true })

wa.weapons.replace({
  sprites = { "sprites/my_bullet", trail.BEAM, trail.GLOW,
    fx.SPARK, fx.BLOB, fx.SMOKE },
})
```

The effect manager's spark, glow and smoke sheets are SDK-owned too. A consumer
can override `spark`, `blob` or `smoke` in `fx.install` with its own paths.

`trail.BEAM` and `trail.GLOW` are qualified `wf-lib/effects/...` asset paths.
Put both in the component's `sprites` table; the engine resolves them from this
bundle's `asset_namespace`.

The `wf-lib/` prefix is the shared-import namespace, not a required folder. A
library bundle can live at `Mods/effects_sdk` (as this test copy does) or under
`Mods/wf-lib/effects_sdk`; the export name and `asset_namespace` decide how it
is imported.

## Modules

- `libs/trail.lua` — PX's effect-manager trail; one trail per round, sampled in
  game frames from a WA missile or a Lua actor and drawn with `wa.draw.ribbon`.
- `libs/px_effects.lua` — PX's effect manager: reach arcs, the electric
  explosion, spark, glow, smoke and crater. Its spark, glow and smoke sheets
  are SDK-owned; a consumer can override them in `fx.install`.
  `fx.ring`/`fx.thin_spin` widths are full `wa.draw.ribbon` widths: PX's half
  widths are doubled in the module, and the `core_w`/`glow_w` overrides are
  full widths too. Small rings floor the core (and thin-spin maximum) at 6.4 px
  full, about 2 px visible through the beam texture, so tiny saws stay legible.
