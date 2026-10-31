Example bundles. Copy a folder to `WormForge/Mods/` next to `WA.exe`, then pick one of
its profiles under **Bundled profiles** in the loader's profile line, where it
has one, or add its weapons (**Manage Weapon Panel**) and add-ons (a click on
its card) to your own profile. Nothing in a bundle runs until a profile selects it, and a
weapon goes wherever the profile places it: its code never names a slot, it
names weapons by id (`guide.moon_grenade`, `stock.bazooka`).

None of these ships to players. The packs that do are `mods/px/` (Project X's
weapons, with Highlander and Kill the King), `mods/utilities/` (Utilities, Fog
of war, +N Seconds and the Cursor) and `mods/sdk/`.

- `starting_guide` (`example.starting_guide`) — the example of the
  [WormForge starting guide](https://github.com/EdLud/WormForge/blob/main/docs/starting-guide-1-your-first-mod.md),
  growing part by part. Part 1: `guide.moon_grenade`, WA's Grenade with about
  a third of the gravity, one burst in four digging a crater (`on_explode`,
  `wa.random`, `wa.land.cut`, a HUD line); `profiles/Moon Grenade.toml`
  places it beside WA's Grenade.
- `pooz` (`example.pooz`) — selecting the weapon possesses the worm as a
  humanoid runner (run/sprint, coyote time at edges, double jump). A/D, W to
  jump, Shift. Switch weapon to drop out.
- `turret` (`example.turret`) — Space plants a persistent Lua turret, placed
  as WA places a mine. Line of sight is `wa.land.trace`; rounds are
  `worm:hurt` and a shove, not explosions.
- `tools` (`example.tools`) — add-ons for diagnostics and testing:
  - `tools.hello` — logs the turn phases and every hurt.
  - `tools.perf` — the FPS counter (top right: live fps, the 2 s average, and
    the longest frame of the last 5 s in ms) and the profiler, which writes a
    `perf:` line to `wkLua.log` every 10 s with each part of a rendered frame.
    Presentation only, so safe online.
  - `tools.worm_state_logger` — one HUD line with the active worm's raw state
    and every change logged to `wkLua.log`, for naming WA's worm states.
  - `tools.audit` — offline native firing through `worm:input`, with home and
    cyclically moved stock profiles and a comparison tool. Requires the optional
    `input-audit` test build; see [audit setup](tools/audit/README.md).
  - `tools.stress` — WA's projectiles against ours, to record and replay: 40
    stock missiles, then 40 Lua actors from the same positions, drawn on the
    GPU in four styles, then Highlander's magnets, Bowling Ball Strikes and
    Electric Grenades. Its sprites load as assets (`wa.assets.load`).
  - `profiles/Diagnostics.toml` ticks the counters over the lobby's weapons;
    `profiles/Stress.toml` places the three Highlander weapons the stress test
    fires (it needs `mods/px` too).

Profiles own their game scheme too: unset settings take Intermediate. Use the
loader's **Manage Scheme (.WSC)** page or a profile's `[scheme]`; gravity and
wind have moved there from Utilities. See [profile scheme settings](../../docs/profile-scheme.md).
