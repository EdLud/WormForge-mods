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

Copy the `wfws_sdk` folder into `WormForge/Mods/` (any folder name works; the
dependency id is what matters). The editor's exported bundles declare
`wfws.sdk`, so it only needs to be installed once next to `wf.sdk` and
`effects.sdk`.

## Why it exists

PX's `px_sprite_builder` draws one sheet for the primary missile. This fork adds
two more layers:

- **Identity** (once, on a missile's first sight): primary, cluster bit, or a
  named extra role.
- **State** (every `pre` phase): homing, digging, roaming, gas... Each state can
  swap the sheet/animation or hand the missile back to WA.

That is what allows a weapon to give its cluster bits different art from its
main round, and to give a behaviour (homing, dig, gas) its own sheet.

## API

```lua
sb.flight(ctx, {
  weapon = ctx.id,
  sheet  = "sprites/<mod>/missile.png",
  anim   = "track",              -- track | rotation | slow | medium | fast | none
  cyclical = 32,                 -- frames in the sheet (optional)
  anim_speed = 1.0, spin = 1.0, scale = 1.0, mirror = true, z = 5.0,

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

The default classifier is `m.sprite ~= 0` at first sight: a **primary** keeps
`sprite = 0`, a **cluster bit** keeps a nonzero stock id (`clustlet`). The
generator writes `sprite = 0` on the primary unconditionally and forces a stock
bit sprite, so both roles classify correctly even with an imported `.wep`.

### State signals

WA writes a nonzero `m.sprite` when a missile changes behaviour. The builder
records the last nonzero value before zeroing, so `sig` matches the record's own
sprite fields:

| state | record field |
|---|---|
| homing (main) | `missile.homing.sprite` |
| homing bit | `clusters.bit.homing.sprite` |
| dig | `dig.dive_sprite`, `dig.sprite_1..3` |
| roam flight | `sheep.flight_1`, `sheep.flight_2` |
| gas | `roam.gas.animal_sprite` |

Each active state needs a **distinct** nonzero id. The editor assigns one when
the record field is empty and warns about duplicates.

### Native hand-back

A state with `native = true` drops the follower and restores the last signal id
to `m.sprite`. Use it to let WA draw the dig frames or a stock homing pose while
the rest of the weapon keeps custom art.

## Verify in game

These are engine behaviours, not static checks:

- `m.sprite` is writable in `pre`, and WA draws it again after `native = true`.
- WA writes the behaviour sprite when it changes; one write is enough.
- Dig: if `sprite_1..3` are written to `m.sprite` over time, list them all in
  `sig`; if they are drawn separately, use `when = function(m) ... end`.
- A state swap despawns and respawns the follower; watch for a one-frame flicker.
- Roaming: check the `pre` phase still runs while the animal is on the ground.
