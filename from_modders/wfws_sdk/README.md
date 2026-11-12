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

  homing = {                     -- art while the missile homes (optional)
    arm = 500, time = 2000,      -- ms after firing; time = 0 homes until it lands
    sheet = "sprites/<mod>/homing.png", anim = "track",
  },
  dig = true,                    -- cycle the sheet while the nose is in the land
  -- dig = { probe = 6, spread = 3, hold = 3, need = 2 }

  bits = {                       -- cluster-bit art; it can have `homing` too
    sheet = "sprites/<mod>/bit_flight.png",
    anim = "rotation", cyclical = 32,
  },
  -- bits = "inherit"            -- bits use the primary art
  -- omit bits entirely         -- bits keep their stock sprite

  states = {
    { scope = "main", when = function(m) return m.vy > 0 end,
      sheet = "sprites/<mod>/falling.png" },
    { scope = "bit", when = function(m) return m.vy > 0 end, native = true },
  },
})
```

### Identity

Each missile is sorted once, the first frame the builder sees it:

1. a `roles` entry whose `match(m)` is true;
2. `is_bit(m)`, when the weapon passes one;
3. `m.bit`, when the engine gives it;
4. otherwise, with a `bits` sheet set, the missile whose `m.sprite` is 0 is a
   cluster bit: a bit starts from the copy of its parent, which the builder
   has already zeroed. Without a `bits` sheet every missile is the primary.

### Homing

Homing is timed. WA arms the missile `arm` ms after firing and steers it for
`time` ms, and a game frame is 20 ms on every machine, so the builder swaps to
the `homing` art for that window. Use the homing delay and duration from the
record.

### Digging

`dig` gives no new art. While at least `need` of four probes, `probe` pixels
ahead of the centre and up to `spread` pixels to either side, are in the land,
the sheet points along the heading and cycles its frames. It keeps cycling for
`hold` frames after the nose comes out.

### States

A state is checked every frame, the first match in its `scope` (`"main"`,
`"bit"`, `"any"` or a role name) wins, and it swaps the art. Test it with
`when = function(m) ... end`.

`sig` matches the last nonzero `m.sprite` the builder saw. WA doesn't write a
behaviour sprite into `m.sprite`, which only ever holds the flight sprite, so
`sig` stays only for the bundles that already pass one. New weapons use
`when`, `homing` or `dig`.

### Native hand-back

A state with `native = true` drops the follower and puts the last nonzero
sprite id back in `m.sprite`, so WA draws the missile again while the rest of
the weapon keeps custom art.

## Verify in game

- WA draws `m.sprite` again after a `native = true` state.
- A state swap despawns and respawns the follower; watch for a one-frame flicker.
- Roaming: the `pre` phase still runs while the animal is on the ground.
