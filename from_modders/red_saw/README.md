# PX Saw — WormForge API 4

Port of Project X's stationary saw (`CSaw`, `map_object_saw/scripts/saw_script.txt`).
A saw is planted where a PX saw weapon explodes (or where the random map spawner
puts one), spins forever, slices and pushes enemy worms, and hits nearby mines,
crates, oil drums and missiles. It is invincible and never moves.

`report_saw.md` is the source-verified specification. This README is only the
bundle map.

## Layout

```
px_saw\
├── mod.toml                 # px.saw; both weapons + random feature
├── lib\saw.lua              # controller, circle collision, damage, taze, art
├── weapons\saw_grenade.lua  # saw_grenade_wep.wep + on_explode
├── weapons\saw_place.lua    # saw_place_wep.wep + on_explode
├── weapons\saw_random.lua   # PX random_saws replacement
├── profiles\Saw.toml        # both weapons, no random saws
├── profiles\SawRandom.toml  # both weapons + random feature
├── weps\saw_grenade.wep    # PX records
├── weps\saw_place.wep
├── sprites\saw\             # sawsheet, foldedblades, mask discs, icons
└── sounds\saw\              # four cuts, clank, electric shock
```

Dependencies: `effects.sdk` (`fx.ring` / `fx.thin_spin`), `px.electric`
(`wf-lib/electric/damage` for the taze hold and `wf-lib/electric/taze_mine`
for marking mines), and `wf.sdk` (`PX_POSTURE` / `PX_HANDS` for the worm while
holding).

## Design

- One controller actor per saw. Its sprite is a circular mask disc, hidden by
  drawing it as additive black. The engine stamps that disc into the walk grid,
  so native missiles bounce, worms cannot stand inside, and teleport cannot
  land in the saw. The mask is the largest disc below the Lua circle. The
  controller is pinned to the saw's position with zero speed every frame, as
  PX does, and lives in WA's object layer (`as_object`), so a blast cannot
  shove the mask away or off the map and WA keeps it as a map object. If WA
  frees it anyway, `turn_start` rebuilds it.
- Collision is a Lua circle of radius `100 * size`; actor `body` masks do not
  scale with `a:gfx{scale=}`.
- The art is three `wa.draw.quad` layers: a static inner blade, a rotating
  outer blade, and the rotating team outline. PX's frames are 11: `3/4`,
  `0/1/2`, `5/6/7`, `8`, `9/10`.
- `size` is an int percent option: default 50 (PX's fired saw), editor/map saws
  would be 100. `lib/saw.lua` clamps to `0.1..1.0`; collision radius `10..100`.
- The two PX `.wep` records are overlaid; the saw is spawned from `on_explode`,
  at the explosion point, just in front of objects (PX z=11), with the firing
  worm's visible colour as its team. Both PX records are otherwise unchanged.
  The hold uses `wf.sdk`'s weapon-less worm posture and lower hand, so the worm
  stays visible while aiming and throwing.
- No terrain cut or dig on spawn. A saw may sit embedded or behind terrain; that
  is deliberate (report §8).
- The random feature mimics `random_saws.txt`: one hidden spawner, one saw per
  frame, one slice per saw, vertical terrain trace, 10 fitting attempts and
  shrink/retry. PX's undefined random count falls back to 4. Its z-plane is a
  50/50 split between behind the map and in front of it.

## Known departures / gaps

- The mask disc is a fixed sprite size, not a scaled shape, so it is chosen
  from 8 px..96 px radii. It is always below the Lua collision circle; a
  missile inside the Lua circle for more than 4 frames gets a fallback shove.
- The world query radius used by random spawning is capped at 64 px, so
  large-saw spawn fitting is approximate above 64% size.
- The team outline colour approximates WA's team colours.
- Damage is applied on the electric hit (`damage_now`), then the taze hold runs;
  PX writes damage immediately and holds afterwards.
- A static corpse (0 HP, no velocity; WA's `is_static`) is skipped before any
  hurt, push or taze. Those writes never settle on a static worm.
- A tazed mine keeps WA's stock blast. After it explodes, worms in PX's 116 px
  electric field get the 20-frame artificial taze: 15 damage on release and
  the captured blast push scaled to 116/100, with a trail on the mine. This
  stands in for PX's 1.25x electric replacement blast. The logic lives in
  `px.electric`'s `wf-lib/electric/taze_mine`, so any electric weapon can mark
  a mine.
- PX's `OutlineDmg = 1.0` bug is corrected to frame 10 in the port.

## Validate

```powershell
D:\PXPortingModsToWF\compiler-cli\wfcheck.exe --strict "D:\PXPortingModsToWF\API-4.0\px_saw"
python D:\PXPortingModsToWF\porting-analysis\tools\check_paths.py "D:\PXPortingModsToWF\API-4.0\px_saw"
```
