# Weather FX 8.1.63 — Final Audit

## Scope

Gameplay runtime delta from exact 8.1.62: **only `lib/Tornado.lua`**. Release metadata/tests/gates were added or updated.

## Fixed defects

1. Carry ownership previously relied on collision plus a player flag that Voxel Nexus free movement could bypass or Gen1 `setMap` could clear mid-carry. 8.1.63 asserts native `inputLocked` continuously and guards the overworld input choke point while tornado carry owns the player.
2. 3D seekers reused ordinary scenery deflection. Real Route 1 qualification proved this could trap the seeker in a ~145px orbit. 8.1.63 separates committed-seeker navigation from roamer collision deflection and uses the visible 30px pickup footprint.
3. 2D semantics are explicitly qualified as screen-space only: no 3D tornado field exists during the 2D relocation event.

## Required proofs

- Corrected pickup-semantics regression: **20/20 PASS** on 8.1.63; exact 8.1.62 negative control fails 11/20.
- Existing 2D relocation: **8/8 PASS**.
- Existing 3D relocation: **8/8 PASS**.
- Real-transfer hostile bridge: **5/5 PASS**.
- 3D walk-contact: **8/8 PASS**.
- Safe destinations: **23/23 PASS**.
- 3D Gale tornado: **38/38 PASS**.
- Tornado map persistence: **10/10 PASS**.
- Waterspout presentation: **5/5 PASS**.

## Real host

See `WEATHER-FX-8.1.63-TORNADO-PICKUP-LIVE-PROOF.md`. All three intended player-facing paths are proven in the real Gen1Recomp/Yellow/Voxel stack: 2D screen sweep relocation, 3D ordinary walk-in pickup, and 3D NORMAL 10% seeker self-catch.
