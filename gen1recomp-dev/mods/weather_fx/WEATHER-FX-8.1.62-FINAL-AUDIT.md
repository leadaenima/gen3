# Weather FX 8.1.62 — Final Audit

## Release purpose

Repair the actual player-facing walk-into-a-3D-tornado trigger while preserving 8.1.61's already-repaired cross-map transfer authority.

## Runtime delta

Built directly from exact Weather FX 8.1.61 (`ca03bf8f326037a8a264172bdd33f2d4fc977631c3f3d3d3170b71f7d63bd2fb`). The intended gameplay-runtime delta is exactly one existing runtime file: `lib/Tornado.lua`.

## Root cause

The previous relocation test used a zero-distance contact setup. Real gameplay could differ because the old detector preferred a voxel render-state player pose and required the player anchor to enter a 14px core even though the visible ground vortex/debris footprint is substantially wider. It also had no swept contact test between samples.

## Repair

- live overworld player position first; render snapshot fallback only;
- minimum physical contact envelope 30 world px, aligned with visible ground circulation plus player body;
- swept relative player/tornado collision to prevent tunneling;
- same-map guard for swept contact;
- no change to destination selection or transfer choreography.

## Qualification

The new exact contact regression must fail on untouched 8.1.61 and pass on 8.1.62. Maintained 2D/3D relocation, transfer, safety, persistence, waterspout and 8.1.60+ lightning tests remain mandatory. Exact frozen-ZIP results are recorded in `weather_fx-core-8.1.62-validation.txt`.

## Real live walk-in proof

A clean isolated Gen1Recomp 0.2.53 / Pokémon Yellow / Voxel Nexus 2.0.16 run loaded the final 8.1.62 candidate in true 3D GALE. Viridian City was genuinely loaded first so it was a legitimate visited destination. The source was then Pallet Town `(8,14)` with the live player at `(px=128, py=224)`. A mature ordinary roamer was placed 32 world pixels north, outside the new 30px envelope.

The driver held the engine's real **UP** input. The live player began moving (`py=224 -> 222`) and, before its cell index changed, Weather FX entered `pickup` with `player touched active tornado / suction pickup`. The real engine subsequently logged `map: VIRIDIAN_CITY at (1,16)` and Weather FX logged `tornado carrying player from PALLET_TOWN to escape-safe outdoor map VIRIDIAN_CITY`. Final live result: **PASS — physical walk-in contact caused an actual different-map relocation.**
