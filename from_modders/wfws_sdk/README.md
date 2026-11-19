# wfws.sdk, WFWS Sprite Builder

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

`pingpong` plays a multi-frame sheet forwards and then backwards instead of
looping it hard back to frame 0, which is what art authored to reverse itself
needs (a piston, a swinging hook, an opening jaw). One forwards-and-back pass
takes the same time one loop used to, so `anim_speed` keeps its meaning, and the
two endpoints are not held for a double frame: `cyclical = 6` plays 0, 1, 2, 3,
4, 5, 4, 3, 2, 1 and repeats. It is a builder feature only (WA has no equivalent
on a native sprite), needs `cyclical > 1`, and is available on the primary, the
bits, each role and the `dig` overrides.

`size` and `angle` are the weapon-level knobs the editor's Hold page shows
under **Builder Parameters**: one multiplier for every sheet so one number
resizes the whole weapon, and a rotation offset for art that does not point up
(a sheet drawn pointing right needs `-90`). The offset is applied in the drawn
frame and negated on a mirrored sheet, so the art points the same way on both
sides; tracked art stays tracked and simply gains the offset.

`offset = { x, y }` is the third knob: the art nudged inside its own cell, in
**sheet pixels**, scaled with the art (`size` times the role's `scale`). It turns
with the drawn angle and mirrors with the side, so a sheet whose pivot is not
its centre (a hammer head above the handle, a muzzle 4 px off) stays correct at
every heading. A role's own `offset` replaces the weapon-wide one. Being an art
fix, it never reaches the record.

There is no glow: WA glows only the natives listed in
`wa.assets.load{ wa_sprites }`, and a pack sheet has no glow copy.

`sb.heading(missile_id)` answers "how was this round drawn a frame ago", in
degrees clockwise from up, for anything that needs the art's orientation rather
than the velocity's. The terrain stamp uses it to pick a frame, so a spinning,
cycling or digging round leaves its picture in the land at the angle it was
drawn at; a round this builder never drew (a native sheet, or an id it has
forgotten) returns `nil` and the caller falls back to the velocity heading. The
angle is the world rotation, without the weapon-wide `angle` offset: that offset
corrects art that does not point up, and a stamp's own art does.

`sb.role(missile_id)` is the other half: `"main"`, `"bit"` or a `roles` entry's
name, the identity the classifier decided on that missile's first frame. It is
kept past the despawn, because a claim `on_explode` runs around the frame the
missile leaves and an effect that belongs to the round or only to its frags has
to know which part burst. `nil` means this builder never classified it (another
weapon, or one it left to WA), which is the only case a caller has to fall back
on. Both answers are per missile id, so they are lockstep stable.

The identity is filled by the `wa.on.missile_frame` handler `sb.flight`
registers, and the engine runs a mod's handlers in registration order. A reader
that has to ask on the missile's first frame registers its own handler after
`sb.flight` (the editor's ribbon trail does), so the answer is already there.
One case is undecided on purpose: a missile at a round that was seen on that
same frame, because the engine can list a burst's bits before it drops the
round. That answer stays `nil` for exactly one frame, and the next frame says
whether the round survived (another shot) or went (one of its bits). Waiting is
correct; guessing there is what made cluster bits read as rounds and lose their
ribbon.

```lua
sb.flight(ctx, {
  weapon = ctx.id,
  sheet  = "sprites/<mod>/missile.png",
  anim   = "track",              -- track | rotation | slow | medium | fast | none
  cyclical = 32,                 -- frames in the sheet (optional)
  pingpong = true,               -- play the frames forwards then back (optional)
  anim_speed = 1.0, spin = 1.0, scale = 1.0, mirror = true, z = 5.0,

  -- weapon-wide, applied to every role (primary, bits, states, roles):
  size  = 1.25,                  -- multiplies each role's own `scale`
  angle = -90,                   -- degrees added to the drawn rotation
  offset = { x = 0, y = -3 },    -- art nudged inside its own cell, sheet px

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

The classifier does not use `m.sprite` for identity. That field is WA's render
slot, not the cluster pellet index: a round that hides its own art can carry the
cluster sprite there (a cluster grenade's main missile came out with
`clustlet`), and the pellet flag (`MissileEntity+0x150`) is not exposed to Lua.
The reliable signal is timing:

- the **first** missile of the weapon is the round;
- a missile that first appears within `bit_window` frames (default 8) after the
  round was last seen, **at the round's last position** (`bit_radius`, default
  64 px), is one of its bits, because a cluster burst builds the bits in the
  round's own detonation;
- a missile that appears while another round is still in the air, or away from
  the dead round, is another round (a fire sequence), not a frag.

A missile that is at a round seen on that same frame is the one ambiguous case:
the engine can build the burst and list its bits before it drops the round, so
the builder decides that missile on the next frame, when the round has either
survived (a shot) or gone (one of its bits).

`bits` with no table leaves cluster bits to WA (`bit_cfg` is `NATIVE`).
`bits = "inherit"` draws them with the primary sheet but still calls them bits.
`is_bit = function(m)` overrides the test, and if a build passes `m.bit`
(`MissileEntity+0x150`, the pellet flag) that is used first because it is exact.
`bit_window = <frames>` widens or narrows the burst window for an unusual
record, and `bit_radius = <px>` widens or narrows where its frags are expected.

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
`pingpong`, `scale`, `mirror`, `z`) while digging, reverting cleanly in open air:
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

The game is a 50 Hz lockstep, so one frame is exactly 20 ms on every machine
no guessing and no desync. The generator zeroes `missile.homing.sprite` /
`clusters.bit.homing.sprite` while the builder owns the art, so WA's own homing
sprite cannot draw underneath.

### `anim = "roam"`: the walking preset

WA walks a roaming animal itself, so on the ground the entity has no velocity
and `track` leaves the art pointing at the last heading, a walking animal that
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
right-facing side (`abs(vx)`), and the clamp uses the shortest signed difference
from `rest`. Walking left is a **true horizontal mirror**: the sheet is mirrored
(`facing = -1`) and the drawn angle is negated (`-(deg(rot) + angle)`). The
negation is required because the engine mirrors about the sprite's own vertical
axis; a bare mirror would flip the walking pose top to bottom. The side is kept
in `roam_side` through a straight drop (`vx == 0`). The role's Mirror toggle
still controls this. It replaces `track` for this animation only; the other
roles keep their own `anim`.

### Roaming (the builder owns the flying state)

A roaming animal walks until the turn's player presses Space, and only then
flies. The walk pose is the record `sprite` (normal-flight art only) and the
flown art is `sheep.flight_1/2`, which the generator zeroes (to the unassigned
sentinel 699, a zero would disable the takeoff) so WA's flown sprites do not
draw underneath.

The walk has two routes:

- **`roam = { walk = <id>, fly = <sentinel> }`**, WA can draw the ground pose
  (it is a stock sprite), so the record keeps it and its id is passed along. The
  first missile is the round whatever its `m.sprite` holds, so the classifier
  needs no exception for it; the builder leaves the animal to WA until the
  takeoff: the turn player's synchronized Space edge, or WA moving the flown
  sentinel into the render slot.
- **`roam = true`**, the pose cannot draw (unset, a bundle path, or an imported
  Project X number such as `34464`, which WA reads as an unassigned pack slot).
  The generator zeroes the record `sprite` and the builder draws the animal from
  the first frame with the role's own animation.

The animation is the role's own on the ground and in the air: `track` points
the art along the vector, `rotation` spins it, the strip cycles. Only
`anim = "roam"` distinguishes the two (rest/lean on the ground, tracking in the
air). A "walking" pose that stood upright would ignore `track` for however long
it took to take off, which looks like the animation being broken.

A roaming animal can also fly on art of its own instead of the primary sheet
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

## Worm hold (`sb.hold`)

WA draws the gun on its aiming frames itself (`crates/engine/src/worm_hold.rs`),
from the claim's `hold =` table. That table has no field for an offset, so
`sb.hold` builds it and, only when a feature needs something the engine cannot
express, takes the aiming poses over with quads of the same sheet:

```lua
local hold = sb.hold(ctx, {
  sheet = "sprites/<mod>/hold.png",
  hand = holds.PX_HANDS[2], hand_type = 2, hand_radius = 10, hand_size = 60,
  weap_radius = 6, weap_rotation = 1, weap_radial_rotation = 1, weap_scale = 1,
  frames = 1, anim_speed = 1, keep_while_firing = true, put_away = true,
  cell_w = 64, cell_h = 64,          -- the sheet's cell, in pixels
  offset = { x = 0, y = -4 },        -- forces the quad layer
  keep_firing = true,                -- hold the sheet on WA's firing frames
  fire = {                           -- the firing role, see below
    sheet = "sprites/<mod>/fire.png", cell_w = 64, cell_h = 64, scale = 1,
    frames = 4, anim_speed = 2, ticks = 13, hide_main = true,
    weap_radius = 6, weap_rotation = 1, weap_radial_rotation = 1,
    offset = { x = 0, y = -4 },      -- its own nudge, like the held art's
  },
  silent_sheet = "sprites/<mod>/silent.png",  -- the mute, 1x1 transparent
})
wa.weapons.replace{ copy_from = "stock.bazooka", hold = hold }
```

`sb.hold` returns exactly the engine's key set (`HOLD_KEYS`), so a hold with no
Lua-only feature returns what the editor used to write inline and nothing else
changes: same draw, same speed, no extra atlas slot, no `wa.on.draw` hook.

When the layer is on:

- The engine is pointed at `silent_sheet` (`wa.weapons.hold_sheet(weapon, n)`)
  only while a worm aims with the weapon, and back at sheet 0 the moment nobody
  does. The walk/put-away pose and the fire pose stay the engine's, so PX's
  aiming has no put-away of its own and WA's own retreat is untouched.
- The quads copy the engine's aim branch: `rot = (1 - aim) * PI`, the weapon at
  `rot_w` x `weap_radius` mirrored by `facing`, the drawn angle
  `(PI - PI*aim - PI*(1 - weap_rotation)) * facing`, the hand at `rot_h`, the
  20-frame `grow()` draw-out on the first aim frames (`counter - 1`, so the
  first one is deliberately blank), and the frame from the engine's own 50 Hz
  `phase += anim_speed * 0.03` clock, advanced once per `wa.world.frame()`.
- `visibility = worm` on every quad, so Invisibility and the ghost tint are the
  engine's, and an invisible unrevealed team draws nothing.
- `offset` is in **sheet pixels**, scaled by `weap_scale` (`size`'s aim
  counterpart), turned with the drawn angle and mirrored with the side:
  positive Y is down the sheet, toward the grip. The engine's `weap_radius`
  measures the same way, so the two add up.

`silent_sheet` is appended to `hold.sheets`, which the claim loads by itself, so
the 1x1 PNG needs no `sprites` entry, only the file at the path.

**The hold sheet must be in the weapon's `sprites` list** when the layer is on.
`wa.draw.quad` resolves a pack path through the sprite keys the claim registers,
and a sheet named only by `hold.sheet` is loaded for the engine's own draw but
gets no key: the quad throws "sprite ... is not installed" inside `wa.on.draw`,
the callback aborts before the mute is restored, and the weapon keeps the
engine's static draw. The editor claims the path automatically for a hold that
needs the layer; a hand-written bundle must add it:

```lua
wa.weapons.replace{ copy_from = "stock.bazooka",
  sprites = { "sprites/<mod>/hold.png" },
  params = { gpu_prefix = "sprites/" },  -- optional: the quad draws from the atlas
  hold = hold }
```

`hand_offset = { x, y }` is the same nudge for the hand, in its own cell's
pixels and scaled by `hand_scale`, and it also forces the layer. `hand_rotation`
needs no layer: the engine has the field (`rot + PI*hand_rotation`), so the
editor writes `1 + degrees/180` there and only the layer's quads read it back.

The layer's hand is placed exactly as the engine places it, `grow(counter) *
hand_scale`, **without** `weap_scale` and without the clip's `scale`. The engine
always draws its own hand (`draw_holds` places `config.hand` whatever sheet the
weapon is pointed at), so matching it is what keeps the two coincident: a bigger
quad showed as a second hand on every weapon whose `weap_scale` was not 1. A
nudged hand (`hand_offset`, or a clip's `dx`/`dy`) does move away from the
engine's copy, which is the one visible limit of taking the aim pose over.

### Limiting the aim (`aim_clamp`)

WA's sweep is 180 degrees: 0 is straight down, 0.5 level, 1 straight up, and both
ends are where a held weapon looks worst, because the art leaves its cell and a
cut aimed vertically reads as noise. WA's own bat pipes its aim for that reason,
and a pack cannot, so the layer clamps what it draws instead:

```lua
aim_clamp = { up = 60, down = 60 },  -- degrees either side of level, 0 to 90
```

`worm.aim` and `worm.aim_target` are read-only, but **`worm:input{ aim = deg }`
writes the same target WA's own `control_aim` writes** (+0x24C, Project X's
FireAngle), so the clamp reaches the engine's aim and not only our draw:

- `hold_install_aim_clamp` registers one `wa.on.body_move` hook (worms only) and
  writes the clamped target while the turn's worm holds this weapon and its aim
  is outside the range. `body_move` runs before WA's body step, so WA adds at
  most one of its own aim steps (180/128 of a degree) after the write: the target
  can sit that one step past the limit, never further. One native write, and only
  while the aim is actually out of range. An engine without `body_move` (or
  `worm:input`) logs one line and keeps the drawn clamp;
- the aiming pose stops at the limit too (`hold_clamp_aim`), while the worm's own
  posture strip keeps following the real aim, as it does in game;
- a Space press latches the **clamped** aim, so a swing and a melee strike are
  thrown along it (`[melee] aim clamped 0.000 -> 0.250 ...` says when it bit);
- a `px.fire_seq` burst whose direction comes from the live aim launches along
  it, because the generator wraps `seq_dir`'s aim in `aim_clamped` (`AIM_LO`,
  `AIM_HI`): belt and braces over the first frame, when the native write has not
  landed yet.

The engine always draws its own hand at whatever WA's aim is, so with a clamp on,
`M.hold` parks it at `hand_radius = 0.01` (the same fallback `draw_hand = false`
needs) and the layer draws the clamped one; otherwise two hands show past the
limit.

### A second hand (`extra_hand`)

`HoldSpec` has one hand slot, so a second hand (a support hand on a foregrip, a
two-handed grip) is the layer's:

```lua
extra_hand = {
  sheet = "sprites/<mod>/hand2.png",  -- optional: the first hand's art otherwise
  radius = -6, rotation = 1, radial_rotation = 1, scale = 0.9,
  -- size = 60,  -- optional: the cell in pixels, defaults to the first hand's
  offset = { x = 2, y = -3 },
},
```

- It uses the engine's own hand maths: position at `rot - PI*radial_rotation` x
  `radius` (mirrored by `facing`), drawn angle `rot + PI*rotation`, cell `size`
  scaled by `grow(counter) * scale` (the first hand's rule), and `offset` in the
  hand cell's pixels, mirrored with the side and turned with the drawn angle.
- **`size` is a length in pixels, never a percentage.** The sheet is drawn into
  `size * scale` game pixels, so `size = 90` is a 90 px hand next to the first
  hand's 60 px cell, and `size = 120` is twice it. Leave it unset and it follows
  the weapon's `hand_size`, so `scale = 1` always means "the same size as the
  first hand". `scale` is the size knob (the first hand calls it `hand_scale`).
- `offset` is multiplied by `scale` alone, exactly like the first hand's
  `hand_offset`, so changing the cell never moves the grip off the weapon. The
  editor writes `size = 60` because its two hands are always 60 px cells.
- It carries a swing's `dx`/`dy` with the weapon, so a two-handed swing does not
  slide apart, and it is skipped on the echo ghosts and on the firing pass (the
  firing role has its own hand).
- It forces the layer (`hold_needs_lua`), and its sheet has to be in the claim
  `sprites` like the hold sheet: the quad resolves through the same registry.

### Firing frames (`keep_firing`, `fire`)

WA draws the held sheet on its two firing states (0x6A/0x6B) only while
`h.firing` is set, and only the turn's own fire message sets it: a burst repeats
the shot without one, so from the second shot the sheet blinks every other
frame. `px_hold_art` used to patch that from outside; the layer does it now, so
a hold needs no second library and the art follows the aim geometry exactly.

- **`keep_firing = true`** keeps the held art on the firing frames: the same
  quads as the aim pose, at full size (the engine's `grow()` only applies to the
  aiming counter), with the strip advanced on the firing clock. It is what
  `keep_while_firing` means once the layer draws, and the editor writes it for a
  burst or a firearm. It forces the layer (`hold_needs_lua`).
- **`fire = { ... }`** is a role of its own, drawn over (or instead of) the held
  art: `sheet`, `cell_w`/`cell_h`, `scale`, `frames`, `anim_speed`, `ticks`,
  `hide_main`, its own `weap_radius`/`weap_rotation`/`weap_radial_rotation` and
  its own hand (`hand`, `hand_type`, `hand_radius`, `hand_rotation`,
  `hand_scale`, `draw_hand`).
  - `ticks` is how long the role stays up, in 50 Hz frames, counted from the
    first firing frame of a shot. **0 means "only WA's own two frames"**, which
    is why a firing animation used to flash for a single frame; leave the key
    out for the same behaviour, or set it to one strip cycle
    (`math.ceil(frames * 50 / fps)`).
  - Every frame gap wider than one tick starts a new shot, which rewinds the
    strip.
  - `hide_main = true` skips the held art (and mutes the engine) while the
    firing role shows, so the sheet replaces the gun instead of stacking on it.
  - Frame 0 is up, as everywhere in the builder, and the art is turned by the
    worm's live aim; `hand_size = 60` is the hand cell PX's sheets use.
  - **`cell_w` / `cell_h` are the sheet's own cell**: its width, and its height
    over the frame count (one frame is the whole picture, however wide). The quad
    is drawn at that size times `scale`, so a square cell squashes a wide muzzle
    flash.
  - **`draw_hand = false` hides the role's hand**; leave it out and the hand is
    drawn at `hand_radius`. A bundle that turns the aiming hand off has to write
    it here too, because the firing pass is a separate draw.
  - A strip (`frames > 1`) has to be declared in `mod.toml`
    (`[sprites."<path>"] frames = n`), otherwise the engine slices the sheet by
    its own height / width rule and the frames disagree with `frames` here.
  - **`offset = { x, y }`** nudges the firing art inside its own cell, in sheet
    pixels and scaled with the role's `scale`, the same channel the held art
    has (`hand_offset` for the hand, scaled with `hand_scale`). The firing role
    is always drawn as quads, so unlike the held art's offset it costs no extra
    layer.

### The Space swing (`swing`)

`swing = { ticks, finish, keys = { { t, angle, dx, dy, scale, frame, alpha, fade, ease }, ... } }`
plays a keyframed clip on the held art when the turn player presses Space. It is
data, not Lua: `M.clip_pose` is a pure function of the ticks since the press, so
the simulation decides *when* and the draw decides *how it looks*, from the same
arithmetic the editor's preview runs.

- **The edge is read in the simulation.** `wa.world.keys().space` is the turn
  player's synchronised keyboard, sampled in a `FRAME_FINISH` worm message once
  per 50 Hz frame; `wa.on.draw` must never decide a swing, because its rate is
  the renderer's. The start tick is stored per weapon and worm, and `clip_pose`
  is evaluated from `wa.world.frame() - start`, so every peer plays the same
  frames.
- **One swing at a time, because the game is turn based.** One worm has the turn
  and its player's keyboard is the only input, so the sampler asks for that worm
  (`worm.turn`) and keeps one swing per weapon, not a map per worm. There is no
  second swing to reconcile with, and code that pretends otherwise hides bugs.
- **The swing takes the worm** (`worm:take{ turn = "freeze" }`). The clip is a
  custom animation, so nothing the engine does may end it: WA's own worm states
  are not the clock. A taken worm stays where it is, WA's fire is eaten, and the
  turn timer stops for the clip, so a swing of any length plays in full and a
  worm cannot walk away mid-cut. The aim and facing at the press are latched for
  the whole clip (a swing is one committed motion). When it ends the worm is
  given back with `worm:release(0, 0)`; `finish = "end_turn"` then ends the turn.
- **The art is drawn while the swing runs, not while the worm aims.** The draw
  pass keeps rendering the clip's quads for every tick even if WA has moved the
  worm out of its aim pose (which is what stopped a firing animation after a
  single frame), at full size (there is no 20-frame draw-out to replay), with the
  engine's own sheet muted underneath.
- **A worm handle is not comparable.** `wa.worms.all()` builds a new
  `WormHandle` userdata on every call and the engine defines no `__eq`, so
  `st.worm == w` is false in the next frame even for the same worm. The swing
  keeps the handle for the calls it has to make (`take`, `release`, the strike)
  and compares `worm.id` (team * 16 + index, stable across peers). Comparing
  handles is why a swing once ran, hit and released with no art at all: the draw
  pass thought no swing was in progress.
- **Every channel is relative to the engine's aim pose.** `angle` is degrees
  added to the drawn angle *before* the side mirror (so the art cuts the same
  way both ways round), `dx`/`dy` are sheet pixels in the hold `offset`'s own
  frame, `scale` multiplies the art, `frame` overrides the strip frame and
  `alpha` fades the quad (`wa.draw.quad` takes 0xAARRGGBB and `quad_tint`
  premultiplies it, so fading needs no blend mode). The hand carries `dx`/`dy`
  so it stays with the weapon. `fade = false` on a key makes the opacity step
  like a frame does: it holds the previous key's alpha for the segment and lands
  on this key's value, so a pose that returns the weapon to the worm does not
  fade out on the way home.
- **Easing is the editor's own set:** `linear`, `in_quad`, `out_quad`,
  `inout_quad`, `in_cubic`, `out_cubic`, `inout_cubic`, `out_back`,
  `out_elastic` and `hold`. A frame is an index, not a number to blend, so it
  steps at the end of the segment that names it.
- **`finish = "end_turn"`** hands the turn back (`wa.world.set_turn_clock(0)`)
  when the clip runs out. A weapon whose claim eats WA's fire
  (`eat_fire = true`, which the editor writes whenever the swing is on) never
  leaves a projectile, so without it the worm would sit in its aim pose for ever.
  Leave it out (`finish = "none"`) when a hit box or a custom `on_fire` ends the
  shot itself.

### The ghost trail (`swing.echo`)

`echo = { count, every, fade, blend = "add" | "alpha" }` inside the `swing`
table draws the same clip a few ticks behind itself:

- Ghost `k` is `clip_pose(t - k * every)` at `fade ^ k` opacity, drawn from the
  farthest to the nearest so the live art lands on its own smear. `count` is
  clamped to 1..8 and `every` to at least 1 tick.
- **Nothing is recorded.** The pose is a pure function of the tick, so a ghost
  costs one `clip_pose` and one quad, every peer draws the same smear, and no
  history has to be kept in the simulation.
- `blend = "add"` is the usual choice for a blade (it glows); dark art wants
  `"alpha"`. The blend is set on the reused quad table on every call, so it can
  never leak into the live draw.
- The hand is **not** part of the trail: it is anchored to the worm, and a smear
  of it reads as a bug rather than as motion.
- `echo` only reaches this branch through `swing` (`clip_prepare(spec.swing or
  spec.clip)` normalises it); a bare `spec.echo` still forces the layer but draws
  nothing, which is the old key's behaviour.

### The melee strike (`melee`)

`melee = { radius, width, follow_swing, hit_frame | hits, push = "aim" | { x, y },
power, lift, hit_sound, miss_sound, once, spare_shooter, hit = function(victim, vx,
vy, hit) ... end }` turns the swing into the attack: the weapon fires nothing, and
on each strike's tick a box in front of the worm is tested against the living
worms.

- **The box is the worm's aim, and nothing else.** `worm.aim` is WA's sweep
  (`0` straight down, `0.5` level, `1` straight up) and `worm.facing` is the side,
  so the direction is `(facing * sin(aim * PI), cos(aim * PI))`, world y down.
  No art enters it: `weap_radius` moves the picture and `weap_rotation` turns the
  sheet, and neither changes where the worm points (the two wrong answers before
  this one used the radius, then the sheet's own drawn angle, so the box landed
  behind the striker). `follow_swing` turns the vector by the clip's `angle` at
  the hit frame, mirrored with the side, so a cut catches a worm the aim pose
  would miss.
  `radius` is the reach outward and `width` the arc's half-width; `along` may
  start 3 px behind the worm, so a worm at its feet is still hit.
- **The tick is the clip's**, `hit_frame` frames of 50 Hz after the Space press
  (`0` lands on the press). The swing loop already runs once per game frame, so
  the frame that matches is the only one that strikes and every peer sees the
  same tick.
- **`hits` is a list of strikes**, each with its own tick and throw, which is how
  a combo works:

  ```lua
  hits = {
    { frame = 8,  damage = 10, power = 2, sound = 6 },
    { frame = 16, damage = 12, power = 4, lift = 1, wav = "sounds/x/hit2.wav" },
    { frame = 22, damage = 16, power = 6, lift = 3 },
  }
  ```

  It replaces `hit_frame`/`damage`/`power`/`lift` when present (those stay
  readable for an older weapon), is sorted by frame, and a strike that leaves out
  `power`, `lift`, `vx` or `vy` inherits the weapon's. Every strike tests the same
  box with the clip's angle at *its* frame, and `once` is per strike, so a worm
  that stands in the box for the whole swing takes all three. `hit_frame` stays
  the first strike's frame.
- **A strike can name its own sample** (`sound` / `wav` / `priority` on the row):
  it is played where that strike lands and falls back to the weapon's
  `hit_sound` / `hit_wav` when the row names none, which is how a light jab before
  a heavy finisher is heard as light and then heavy. `wav` is a declared pack
  path, exactly like `hit_wav`.
- **`hit_sound` / `miss_sound`** are WA's own sound ids (0 is silent). Each strike
  plays one: `hit_sound` at the first worm the box took, `miss_sound` at the
  striker when it took nobody, once per strike however many worms it took. A
  swing that comes off nothing is silent without it, because a melee claim eats
  WA's fire and the record's own sound never plays. `96` is WA's grenade throw and
  baseball miss, the editor's default whiff. `wa.sound.play` is `pcall`ed: the
  verb is newer than some engine builds and a missing sound must not cost the
  strike.
- **Targets come from `wa.worms.all()`**, a deterministic list, so the hit set and
  order are identical on every peer. `spare_shooter` (default on) skips the worm
  that swung, `once` (default on) records each victim for that swing, and the flag
  resets on the next Space press rather than on a timer.
- **`log = true`** prints the strike to WormForge's log: the swing's start (tick,
  position, weapon, aim, facing), **one line per worm with its own
  `along`/`across`** and why it was skipped, a summary with the hit tick, the scan
  vector and the reach, and the swing's end. An empty box therefore names its own
  cause (`outside` behind the striker, out of reach, out of the arc), a missing
  `swing at tick …` line means the press never reached the sampler, and
  `[wfws] Space pressed … no hold layer has an entry` means the weapon's layer is
  not installed at all.
- **What a hit does is the weapon's callback**, not the library's: the box test
  passes `(victim, vx, vy, hit)`, the throw the layer computed and the strike that
  landed (`hit.frame`, `hit.damage`, `hit.power`, `hit.lift`), and the callback
  calls
  `victim:hurt{ amount = 24, vx = vx, vy = vy }` or, for an electrical strike,
  `zap.hurt_electric(victim, 24, { push_x = vx, push_y = vy, retain = true })`.
  Damage, kind, sound and any extra effect stay in the weapon, so the SDK needs no
  new hit kinds. A callback that raises is `pcall`ed, so one broken weapon cannot
  take the 50 Hz message down.
- `push = "aim"` throws along the scan vector scaled by `power`; a `{ x, y }`
  table is a fixed throw. `lift` is added to either (positive is up).
- **It needs the swing**, and it forces the layer: `hold_needs_lua` is true for
  `melee`, so `M.hold` registers the entry (and the swing clock) even for a hold
  whose art is centred. Nothing else about the hold changes.
- **The record's own fire type does not matter.** The claim eats WA's fire and
  the swing takes the worm, so a melee weapon is never played by WA's own
  handler. The editor still bases it on the Sheep Launcher rather than WA's
  Baseball Bat: a special melee subtype resolves its whole hit inside one native
  frame, so the worm never stays anywhere long enough to animate, which is what
  made the bat unusable as a base. A power record also keeps WA's aim phase and
  its firing pipeline, so the worm is aiming normally when Space arrives.

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
