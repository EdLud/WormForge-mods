# Random sprites

Stock body / cluster sprite chaos for thrown, shot, and dropped weapons.

- Does **not** touch worm aim / hold sheets.
- Claims slots at load; reshuffles on the first `worm_message` via `wa.random` + `wa.weapons.retarget` (same timing as Highlander's deal).
- Flight look is rewritten on the missile after spawn so throw-aim poses stay stock.
- Empty sheep / HM mode-switch banks are left alone so behaviour stays stock.
- Needs WormForge **0.7.3+** (`wa.weapons.retarget`).

Install via the in-game mod loader ("Check online"), or copy this folder to `Mods/random_sprites`.
