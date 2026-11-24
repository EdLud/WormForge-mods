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

### Who draws what

`fx.install` registers one draw callback per caller and paints the effects that
caller created, which is why a bundle must call it from every component that
makes effects (`wa._mod` is the component's id). A bundle that installs once
from its first weapon is still fine: an effect made by another component of the
same bundle is assigned to that installer and logged once. Without that, an
effect with no callback isn't an error, it is simply invisible.

`trail.BEAM` and `trail.GLOW` are qualified `wf-lib/effects/...` asset paths.
Put both in the component's `sprites` table; the engine resolves them from this
bundle's `asset_namespace`.

The `wf-lib/` prefix is the shared-import namespace, not a required folder. A
library bundle can live at `Mods/effects_sdk` (as this test copy does) or under
`Mods/wf-lib/effects_sdk`; the export name and `asset_namespace` decide how it
is imported.

## Owners

The hidden driver actor that runs a trail or effect needs a real owner;
`wa.actors.spawn` refuses a zero handle. Event fields such as `ev.worm` can be
one (a zero handle is still a truthy userdata), so `trail.add` and the effect
manager fall back to the turn's worm, and skip the effect when there's no turn worm either.

## Trail

`libs/trail.lua` is PX's `SetTrail` effect: one ribbon per round, sampled in
game frames.

- At most `max` points, one every `every` frames while the round moves; the
  oldest drops past the cap.
- `noise` (pixels) jitters each point along the ribbon's own normal from a fixed
  257-entry table, so the wobble is identical on every peer: 0 is the straight
  ribbon, 4 to 9 reads as electricity. `rainbow = true` (or `{ speed, offset }`)
  cycles the hue along the ribbon and with the simulation clock, PX's
  `SetRainbowMode`.
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
  explosion, spark, glow, smoke, rings, emitters and crater. Its spark, glow
  and smoke sheets are SDK-owned; a consumer can override them in
  `fx.install`.
  `fx.ring`/`fx.thin_spin` widths are full `wa.draw.ribbon` widths: PX's half
  widths are doubled in the module, and the `core_w`/`glow_w` overrides are
  full widths too. Small rings floor the core (and thin-spin maximum) at 6.4 px
  full, about 2 px visible through the beam texture, so tiny saws stay legible.
  The burst's `thickness` is PX's half-width for the sharp pass (0.9x) and the
  glow (1x); a `core` half-width in px (at least 1.25) sets the sharp pass
  instead. The stock blast draws over the `EFFECTS` band, so in `effect` mode a
  burst there shows only after the boom; `fx.install{ depth = { burst =
  wa.depth.FRONT } }` draws it over the worms.
- `libs/custom_explosion.lua` - PX's non-electric `do_custom_explosion`:
  falloff damage, push, crater and one effect burst. Call it from `on_explode`
  after zeroing the record's own `explosion.power`. The radial damage goes
  through `wa.world.blast`, PX's `Env->Objs` walk, so worms, mines, crates,
  drums, missiles, arrows and Lua actors whose `body.hit_by` takes blasts are
  all hit; a 0 HP worm WA hasn't started killing gets the same falloff and
  push by hand because the engine leaves it out. `kind = "taze"` (or a
  bundle's own kind) names the hit the recipients read, otherwise it is a
  plain blast. The electric variant stays in `px.electric` because it also
  tazes and chains.

## Rainbow

`burst`, `arc`, `spark`, `glow`, `ring`, the emitter's `trail` and the trail
module itself take `rainbow = true` or `rainbow = { speed, offset }`, PX's
`SetRainbowMode` / `CalculateRainbow`. The hue comes from `HueToRGBLocal`
(centred at 180, so the colour never goes black) and the clock is the
simulation's own frame counter, never a draw callback's: two peers tint the
same frame the same way. `fx.emitter` propagates its own `rainbow` to whichever
parts don't set one, which is what PX's single manager switch does.

## Emitter

`fx.emitter(o)` is PX's `CEffectManager` as a live actor: a hidden driver that
draws a spark, a glow, short reach bolts and optionally a ring and a ribbon at
one point.

```lua
local e = fx.emitter{
  x = ev.worm.x, y = ev.worm.y, owner = ev.worm, preset = "electric",
  follow = function() return m.x, m.y, m.vx, m.vy end,
  ring = { radius = 26, segments = 22, noise = 0.9, speed = 0.07,
    ellipse = { 1.2, 0.45 }, r = 160, g = 200, b = 255 },
  trail = false,
}
```

- `preset` is `"electric"` (`createElectricImpact`) or `"thunder"` (the mine's
  thunder in `px_electric`, one long bolt from below). Every part takes the same
  keys as `fx.arc`, `fx.ring` and `fx.trail`, so a preset is only a starting
  table. A part may also be a plain flag: `spark = true` means "on with the
  preset's numbers" (any non-table override is ignored), and `trail = false`
  turns the emitter's own ribbon off. Only a table overrides fields.
- `follow` is the anchor: return `x, y, vx, vy` each frame, or nothing when the
  thing it rides is gone, which ends the emitter. `move_to(x, y)` moves it by
  hand, `reach_to(x, y)` adds one bolt, `burst{...}` bursts and removes it.
- `ring` is an `fx.ring` around the same point. `ellipse = { x, y }` bends it
  (PX's `circumference`/`circumferenceSin`): 1.2 x 0.45 is the lens a railgun
  travels in. The ring rides the emitter when it has no `follow` of its own.
- `ring.track = true` points the bend along the owner's heading
  (`wa.math.atan(vy, vx)`), so a lens ring faces where the round is going: the
  long axis is `x` of the ellipse. `ring.angle` then becomes an offset from that
  heading, and `ring.speed` isn't applied, because the heading is written every
  frame and a spin couldn't accumulate. A ring whose owner has no velocity (a
  muzzle emitter moved by `move_to`) keeps its own angle and spins.
- `rainbow`, `ring.rainbow`, `trail.rainbow` as above. `trail = false` keeps the
  emitter's own ribbon off; the trail module is normally the round's job.

The emitter is turn based like everything else in a bundle: one per weapon is
enough, since only the turn's worm aims or fires. Everything the module makes
shares one hidden driver (a refcounted actor per match, not per effect), so PX's
red saw, which wants three rings on one object, is three `fx.emitter` calls with
three radii, and it costs three tables and no extra actor. A muzzle emitter moves from
`wa.on.body_move` (`worm.aim` and `worm.facing` give the fire angle, PX's
`curDist` the offset), and `on_fire` hands it to the missile WA built.
