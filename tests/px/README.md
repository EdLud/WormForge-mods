# PX development tests

This directory stays outside the installable `px/` pack. It contains mock WA
environments, assertions, a baseline and the Highlander profile fixture;
downloads and replay packs contain the runtime code instead.

From the mods repository root:

```sh
for test in tests/px/test_*.lua; do lua "$test" || exit; done
```

From an engine checkout, prefix those paths with `mods/`. Individual scripts
can also run from another working directory using their full path. The Rust
integration tests supply `HIGHLANDER_ROOT` to locate the same runtime pack.

- `test_match.lua` exercises the full match and weapon behavior against mock WA.
- `setup_match.lua` reads `px/mod.toml` and `fixtures/Highlander.toml`, then
  installs the actual runtime components for that mock match. Its small profile
  parser belongs only to tests; installed mods use the engine's loader.
- `baseline.txt` records the expected claims, hooks and deals. Update it with
  `lua tests/px/test_match.lua --baseline` only for an intended behavior change.
- The other `test_*.lua` scripts cover pools, portals, zones, bunkers and turrets.

Gameplay code remains in `px/weapons/` and `px/scheme/highland_rules.lua`.
