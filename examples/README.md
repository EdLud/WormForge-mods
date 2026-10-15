Example bundles. Copy a folder to `WormForge/Mods/` next to `WA.exe`, then pick one of
its profiles in the loader's Profile tab, or add its weapons and add-ons to
your own profile. Nothing in a bundle runs until a profile selects it, and a
weapon goes wherever the profile places it: its code never names a slot, it
names weapons by id (`labs.cut_lab`, `stock.bazooka`).

Project X's weapons, and Highlander's rules as an add-on, are not examples:
they are the `px.ports` bundle in `mods/px/`.

- `component_demo` (`example.components`) — the smallest bundle: two weapons
  built on WA's Bazooka and Mortar, and an add-on with a setting. Its README
  walks through the format; `profiles/Demo.toml` places them.
- `utilities` (`core.utilities`) — one add-on, Utilities, with match settings
  (gravity %, wind, heal at turn start) and switches for ExTurnSide, Agility,
  Live HP and the collect viewer.
- `labs` (`example.labs`) — one small weapon per part of the API, each in its
  own folder or file; `profiles/Labs.toml` places them all.
  - `labs.cut_lab` — WA's Bazooka cuts a hole of the chosen shape where it
    lands (+ cycles the shape, 1-9 and 0 the size): `wa.land.cut`.
  - `labs.hurt_lab` (Ten) — Space eats WA's punch and `worm:hurt(10)`s every
    enemy.
  - `labs.echo_mine` — WA's mine: the first proximity puffs dirt, the boom
    sprays five bananas with exhaust trails. `on_proximity` and `on_explode`
    as data.
  - `labs.panel_icon` — a pack PNG as the panel icon.
  - `labs.worm_toss` — the land cursor: click-hold a worm to drag it, release
    to throw.
  - `labs.q_bazooka` (add-on) — Q selects WA's Bazooka, wherever it is placed;
    Space charges and fires it as usual.
  - `labs.rec_*`, the Record Lab — ten copies of WA's Bazooka and one of its
    Grenade, each with one field of its weapon record changed raw, to settle what the field does;
    the HUD names both readings. `profiles/Record Lab.toml` places them beside
    WA's Bazooka and Grenade, with infinite ammo.
- `gif_donkey` (`example.gif_donkey`) — Growth Hormones, written twice: as
  data flags the engine runs (`gif.flags`) and as Lua (`gif.lua`). Both can be
  placed side by side; `profiles/Growth Hormones.toml` does that.
- `gravler_strike` (`example.gravler_strike`) — WA's Mole Squadron with PX's
  four Gravler sprites swapped in (`mole_dig_rotation`). PX weapon-data tuning
  is pending comparison.
- `pooz` (`example.pooz`) — selecting the weapon possesses the worm as a
  humanoid runner (run/sprint, coyote time at edges, double jump). A/D, W to
  jump, Shift. Switch weapon to drop out.
- `turret` (`example.turret`) — Space plants a persistent Lua turret, placed
  as WA places a mine. Line of sight is `wa.land.trace`; rounds are
  `worm:hurt` and a shove, not explosions.
- `wormcraft` (`example.wormcraft`) — aimed as WA's Cluster Bomb; the shot
  plays an anime cut-in (speed lines and portrait) with `cutout.mp3`, then
  writes `WormCraft` letter by letter.
- `KillTheKing` (`example.kill_the_king`) — Project X's Kill the King game
  mode, as an add-on.
- `tools` (`example.tools`) — add-ons for diagnostics and testing:
  - `tools.hello` — logs the turn phases and every hurt.
  - `tools.perf` — the FPS counter (top right: live fps, the 2 s average, and
    the longest frame of the last 5 s in ms) and the profiler, which writes a
    `perf:` line to `wkLua.log` every 10 s with each part of a rendered frame.
    Presentation only, so safe online.
  - `tools.worm_state_logger` — one HUD line with the active worm's raw state
    and every change logged to `wkLua.log`, for naming WA's worm states.
  - `tools.stress` — WA's projectiles against ours, to record and replay: 40
    stock missiles, then 40 Lua actors from the same positions, drawn on the
    GPU in four styles, then Highlander's magnets, Bowling Ball Strikes and
    Electric Grenades. Its sprites load as assets (`wa.assets.load`).
  - `profiles/Diagnostics.toml` ticks the counters over the lobby's weapons;
    `profiles/Stress.toml` places the three Highlander weapons the stress test
    fires (it needs `mods/px` too).
