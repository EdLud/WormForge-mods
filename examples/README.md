Example packs. Copy a folder to `Mods/` next to `WA.exe`.

- `hurt_lab` — overlays **fire punch** as **Ten**. Space is lockstep `FIRE_WEAPON`: eat the punch, `worm:hurt(10)` every enemy. Needs no other fire_punch overlay.
- `circle_bazooka` — overlays bazooka with `sprites/ball.png` (8-frame spin), gravity 25, wind 200, extra Lua bounce. Do not enable together with `ice_bazooka`.
- `gif_donkey` — grenade slot Growth Hormones via **statuses** (checkboxes: gravity, collide, persist, drown, explode). GUI path.
- `gif_donkey_lua` — same weapon via **Lua verbs**. `on_click` is a function that calls `wa.actors.spawn`; the brain ticks gravity/move/explode. `wa.land` / `wa.worms` / `wa.crates` are available. Disable `gif_donkey` if both are in `Mods/` (same slot).
- `wormcraft` — overlays **cluster bomb**. Aiming keeps the stock cluster sprite. Shot plays an anime cut-in (speed lines + portrait) with `cutout.mp3`, then writes `WormCraft` letter by letter and the meme sting. Needs no other cluster_bomb overlay.
- `worm_toss` — overlays **battle axe**. Strike cursor, click-hold a worm to drag (stock airborne physics / wiggle), release to throw or drop.
- `pooz` — overlays **shotgun** as a panel slot only. Selecting it possesses the owner as the humanoid runner (run/sprint, coyote mode in edges, double jump). A/D, W to jump, Shift. Switch weapon to drop out. Needs no other shotgun overlay.
- `q_bazooka` — use bazooka even when its not on panel or in scheme. On your turn, **Q** stock-selects bazooka. **Space** hold charges the power bar; release shoots. Same as a real bazooka.
