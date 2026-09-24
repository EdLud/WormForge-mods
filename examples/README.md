Example packs. Copy a folder to `Mods/` next to `WA.exe`.

- `highlander` — verb-based gameplay/rules pack with no weapon slot. Deals each worm a deterministic virtual arsenal, materializes only the active worm's hand, and transfers a dead worm's weapons to the turn worm. Demonstrates `wa.inventory`, `wa.on.turn_start`, and `wa.on.death`.
- `highlander_pure_lua` — the same rules before those verbs existed: per-worm tables, turn filtering, death polling, and transfers are all written by hand. Educational comparison only; enable one Highlander edition at a time.
- `mask_lab` — overlays **prod**. **Experimental** actor masks: click places an animated GIF whose walk/hit solid tracks each frame (`mask = true` + worm/land/weapon/actor checkboxes). Also ships `sprites/fox.png` for a static silhouette. Needs no other prod overlay.
- `hurt_lab` — overlays **fire punch** as **Ten**. Space is lockstep `FIRE_WEAPON`: eat the punch, `worm:hurt(10)` every enemy. Needs no other fire_punch overlay.
- `turret` — overlays **dynamite**. Space plants a persist sentry (mine placement). Line of sight is `wa.land.trace`; rounds are `worm:hurt`, not explosions. Needs no other dynamite overlay.
- `circle_bazooka` — overlays bazooka with `sprites/ball.png` (8-frame spin), gravity 25, wind 200, extra Lua bounce. Do not enable together with `ice_bazooka`.
- `gif_donkey` — grenade slot Growth Hormones via **statuses** (checkboxes: gravity, collide, persist, drown, explode). GUI path.
- `gif_donkey_lua` — same weapon via **Lua verbs**. `on_click` is a function that calls `wa.actors.spawn`; the brain ticks gravity/move/explode. `wa.land` / `wa.worms` / `wa.crates` are available. Disable `gif_donkey` if both are in `Mods/` (same slot).
- `wormcraft` — overlays **cluster bomb**. Aiming keeps the stock cluster sprite. Shot plays an anime cut-in (speed lines + portrait) with `cutout.mp3`, then writes `WormCraft` letter by letter and the meme sting. Needs no other cluster_bomb overlay.
- `worm_toss` — overlays **battle axe**. Strike cursor, click-hold a worm to drag (stock airborne physics / wiggle), release to throw or drop.
- `super_drill` — overlays **pneumatic drill**. WA performs its normal randomized drill; an invisible watcher stamps a second stock drill mask at the worm each frame while drilling, as PX's Super Drill does. Use matching DLLs and packs for network testing; do not enable another pneumatic drill overlay.
- `gravler_strike` — overlays **concrete donkey** with WA's Mole Squadron strike and digging behavior. PX's Gravler artwork and data tuning are pending comparison; do not enable another donkey overlay.
- `pooz` — overlays **shotgun** as a panel slot only. Selecting it possesses the owner as the humanoid runner (run/sprint, coyote mode in edges, double jump). A/D, W to jump, Shift. Switch weapon to drop out. Needs no other shotgun overlay.
- `q_bazooka` — use bazooka even when its not on panel or in scheme. On your turn, **Q** stock-selects bazooka. **Space** hold charges the power bar; release shoots. Same as a real bazooka.
- `mine_emit` — overlays **mine**. First proximity puffs dirt, boom sprays five bananas with exhaust trails. Needs no other mine overlay. Console: `echo proximity` / `echo explode`.
