# wfws.sdk — WFWS Sprite Builder

The editor's own flight-art builder. It is a **library bundle**: it has no
components and never appears on the weapon panel. A weapon bundle depends on it
and imports the module:

```toml
dependencies = ["wfws.sdk"]
```

```lua
local sb = require("wf-lib/wfws_sprite_builder")
```

`wfws.sdk` depends on `wf.sdk`, so the hold builder (`wf-lib/holds`) keeps
working and `sb.PX_POSTURE` / `sb.PX_HANDS` are still available.

## Install

Copy the `wfws_sdk` folder into `WormForge/Mods/wf-lib/` (any folder name works;
the dependency id is what matters), next to `wf-lib/sdk` (`wf.sdk`) and
`wf-lib/effects_sdk` (`effects.sdk`). The editor's exported bundles declare
`wfws.sdk` and ship this folder at `wf-lib/wfws_sdk/`, so unpacking a ZIP into
`Mods/` puts it in the right place; it only needs to be installed once.

## Why it exists

PX's `px_sprite_builder` draws one sheet for the primary missile. This fork adds
two more layers:

- **Identity** (once, on a missile's first sight): primary, cluster bit, or a
  named extra role.
- **State** (every `pre` phase): homing, digging, and the roaming take-off. Each
  state can swap the sheet/animation or hand the missile back to WA.

That is what allows a weapon to give its cluster bits different art from its
main round, to time homing art by the record's own window, and to animate a
roaming animal's flight.

## API

`size` and `angle` are the weapon-level knobs the editor's Hold page shows
under **Builder Parameters**: one multiplier for every sheet so one number
resizes the whole weapon, and a rotation offset for art that does not point up
(a sheet drawn pointing right needs `-90`). The offset is applied in the drawn
frame and negated on a mirrored sheet, so the art points the same way on both
sides; tracked art stays tracked and simply gains the offset.

There is no glow: WA glows only the natives listed in
`wa.assets.load{ wa_sprites }`, and a pack sheet has no glow copy.

```lua
sb.flight(ctx, {
  weapon = ctx.id,
  sheet  = "sprites/<mod>/missile.png",
  anim   = "track",              -- track | rotation | slow | medium | fast | none
  cyclical = 32,                 -- frames in the sheet (optional)
  anim_speed = 1.0, spin = 1.0, scale = 1.0, mirror = true, z = 5.0,

  -- weapon-wide, applied to every role (primary, bits, states, roles):
  size  = 1.25,                  -- multiplies each role's own `scale`
  angle = -90,                   -- degrees added to the drawn rotation

  roam = true,                   -- roaming animal (see below)
  -- roam = { walk = 153, fly = 699 }  -- WA draws the walk; the ids it uses

  bits = {                       -- cluster-bit art
    sheet = "sprites/<mod>/bit_flight.png",
    anim = "rotation", cyclical = 32,
  },
  -- bits = "inherit"            -- bits use the primary art
  -- omit bits entirely         -- bits keep WA's own sprite

  states = {
    { scope = "main", sig = 245, sheet = "sprites/<mod>/state_homing.png",
      anim = "track" },
    { scope = "bit", sig = 246, sheet = "sprites/<mod>/state_homing_bit.png" },
    { scope = "main", sig = { 247, 248 }, native = true },  -- hand back to WA
  },
})
```

### Identity

The default classifier distinguishes the primary missile from cluster bits using
`m.sprite`: the generator zeroes the primary's `sprite` in the record (so the
primary spawns with `m.sprite == 0`), while cluster bits keep a nonzero stock
sprite (e.g. `clustlet` = 54). Therefore, a missile is classified as a cluster bit
when `m.sprite ~= 0`.

When no `bits` table is configured, `bit_cfg` defaults to `NATIVE`: cluster bits are
left untouched so WA draws them natively. `bits = "inherit"` draws cluster bits with
the primary sheet. `is_bit = function(m)` overrides the test, and if the engine ever
passes `m.bit` (MissileEntity+0x150, the pellet flag) that is used first because it
is exact.

`log = true` prints the first three frames of each missile
(`id`, `sprite`, `ident`) so the classification can be checked in the log.

### State signals

WA writes a nonzero `m.sprite` when a missile changes behaviour. The builder
records the last nonzero value before zeroing, so `sig` matches the record's own
sprite fields:

| state | record field |
|---|---|
| homing (main) | `missile.homing.sprite` |
| homing bit | `clusters.bit.homing.sprite` |
| dig | `dig.dive_sprite`, `dig.sprite_1..3` |

Each active state needs a **distinct** nonzero id. The editor assigns one when
the record field is empty and warns about duplicates. Roaming is not here: its
walk/flight/gas art are separate record fields, not `m.sprite`.

### Digging (no state, no sheet)

A digging record names no art of its own: `dig.dive_sprite` and
`dig.sprite_1..3` are zeroed (WA's mole is 158-161, and PX's `wsvr/wsvru/wsvrd/
wsvb` are 245-248 -- ids that would be drawn underneath our sheet). Digging is
then only an animation: `dig = true` makes the builder probe the terrain around
the nose every frame (four samples across the heading, two hits = digging, PX's
Bunker Buster test) and cycle the role's own sheet frames while it is in the
land, keeping the heading locked. You can tune the probe or override the
underground animation and transform (`anim`, `spin`, `anim_speed`, `cyclical`,
`scale`, `mirror`, `z`) while digging, reverting cleanly in open air:
`dig = { anim = "fast", spin = 2.5, anim_speed = 1.8, probe = 6, spread = 3, hold = 3, need = 2 }`.

A weapon cannot start digging later in its life: the action is fixed when the
record is installed, so "is this missile digging" is purely terrain contact.

### Homing (timed)

Homing is a window, not a sprite id: WA arms the missile `arm` ms after it is
fired and steers it for `time` ms (`0` = until it lands or blasts). Pass the
record's own numbers with the art and the builder draws it only in that window:

```lua
sb.flight(ctx, {
  weapon = ctx.id, sheet = "sprites/<mod>/missile.png",
  homing = { arm = 800, time = 6000,
             sheet = "sprites/<mod>/state_homing.png", anim = "rotation" },
  bits = { sheet = "sprites/<mod>/bit_flight.png",
           homing = { arm = 400, time = 3000, sheet = "sprites/<mod>/state_homing_bit.png" } },
})
```

The game is a 50 Hz lockstep, so one frame is exactly 20 ms on every machine —
no guessing and no desync. The generator zeroes `missile.homing.sprite` /
`clusters.bit.homing.sprite` while the builder owns the art, so WA's own homing
sprite cannot draw underneath.

### `anim = "roam"`: the walking preset

WA walks a roaming animal itself, so on the ground the entity has no velocity
and `track` leaves the art pointing at the last heading — a walking animal that
looks frozen. `anim = "roam"` holds a ground pose and lets the art lean a little
while the animal steps; **in the air it tracks the velocity exactly like
`track`**, so a flying animal points where it flies:

```lua
sb.flight(ctx, { weapon = ctx.id, sheet = "...", anim = "roam",
                 tilt = { up = 25, down = 25, rest = 90 } })  -- degrees
```

`rest` is the walking pose (`90` lays a sheet that points up along the ground),
and `up`/`down` are how far the art may lean above/below it as it steps. Below
0.05 px/frame the art sits at `rest`. The ground heading is measured on the
right-facing side, and the clamp uses the shortest signed difference from
`rest`. Walking left **turns the whole pose through the left** instead of
mirroring the sheet: the engine mirrors a sprite about its own vertical axis,
which becomes a top-to-bottom flip once the pose lies flat, so `anim = "roam"`
never sets `facing` (its role's Mirror toggle is ignored). The airborne pose is
tracked on both sides and needs no mirror either. It replaces `track` for this
animation only; the other roles keep their own `anim`.

### Roaming (the builder owns the flying state)

A roaming animal walks until the turn's player presses Space, and only then
flies. The walk pose is the record `sprite` (normal-flight art only) and the
flown art is `sheep.flight_1/2`, which the generator zeroes (to the unassigned
sentinel 699 — a zero would disable the takeoff) so WA's flown sprites do not
draw underneath.

The walk has two routes:

- **`roam = { walk = <id>, fly = <sentinel> }`** — WA can draw the ground pose
  (it is a stock sprite), so the record keeps it and its id is passed along. It
  is the one nonzero `m.sprite` that means *primary*, not bit, so the classifier
  needs it, and the builder leaves the animal to WA until the takeoff: the turn
  player's synchronized Space edge, or WA moving the flown sentinel into the
  render slot.
- **`roam = true`** — the pose cannot draw (unset, a bundle path, or an imported
  Project X number such as `34464`, which WA reads as an unassigned pack slot).
  The generator zeroes the record `sprite` and the builder draws the animal from
  the first frame with the role's own animation.

The animation is the role's own on the ground and in the air: `track` points
the art along the vector, `rotation` spins it, the strip cycles. Only
`anim = "roam"` distinguishes the two (rest/lean on the ground, tracking in the
air). A "walking" pose that stood upright would ignore `track` for however long
it took to take off, which looks like the animation being broken.

A roaming animal can also fly on art of its own instead of the primary sheet —
`roam` carries the role's keys when it does:

```lua
sb.flight(ctx, { weapon = ctx.id,
                 sheet = "sprites/<mod>/missile.png",
                 anim = "track", cyclical = 32,
                 roam = { sheet = "sprites/<mod>/state_roam.png",
                          anim = "roam", cyclical = 8, scale = 1.5,
                          walk = 153, fly = 699 } })
```

Without the builder, the claim key installs the two WA flying sheets instead.
Each is a rotation strip (WA picks the cell from the heading, frame 0 up,
clockwise; PX's Ghost Sheep ships 32 cells) and WA alternates the pair for the
cape sway:

```lua
sheep_sprites = { "sprites/<mod>/sheep_flight1.png", "sprites/<mod>/sheep_flight2.png" }
```

Exactly two are required. The walking and gas poses stay record fields.

### Native hand-back

A state with `native = true` drops the follower and re-applies the last signal
id to `m.sprite`. For a *primary* that id is not the record's own art (the
generator zeroed it to classify), so native is only safe while the record still
names a real sprite; it is being replaced by per-feature native routes (dig:
leave the record's indexes alone; roam: `sheep_sprites`; homing: the homing
sprite field).

## Verify in game

These are engine behaviours, not static checks:

- `m.sprite` is writable in `pre`, and WA draws it again after `native = true`.
- `m.sprite` is the *flight* sprite only: WA does not write homing/dig/gas
  sprites into it, so `sig` matching is a legacy path. Time the state or probe
  for it instead.
- Dig: the probes find the crater walls; watch that the animation starts at the
  first contact and that no mole or `wsv*` frame appears under the sheet.
- A state swap despawns and respawns the follower; watch for a one-frame flicker.
- Roaming: check the `pre` phase still runs while the animal is on the ground.
