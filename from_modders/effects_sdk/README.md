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

## Owners

The hidden driver actor that ticks a trail or effect needs a real owner;
`wa.actors.spawn` refuses a zero handle. Event fields such as `ev.worm` can be
one (a zero handle is still a truthy userdata), so `trail.add` and the effect
manager fall back to the turn's worm, and skip the effect when there is none.

## Trail

`libs/trail.lua` is PX's `SetTrail` effect: one ribbon per round, sampled in
game frames.

- At most `max` points, one every `every` frames while the round moves; the
  oldest drops past the cap.
- It draws a sharp core (`core_w`) and a wider glow (`glow_w`). PX's widths are
  half-widths; this module stores the doubled full widths `wa.draw.ribbon`
  wants.
- When the round disappears, the ribbon sheds one point every `vanish` frames
  from the oldest end.
- `trail.sample(id, x, y, vx, vy)` is the fill for a Lua actor; WA missiles are
  sampled from `trail.install`'s own frame callback.

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
- `libs/custom_explosion.lua` — PX's non-electric `do_custom_explosion`:
  falloff damage, push, crater and one effect burst. Call it from `on_explode`
  after zeroing the record's own `explosion.power`; the electric variant stays
  in `px.electric` because it also tazes and chains.
