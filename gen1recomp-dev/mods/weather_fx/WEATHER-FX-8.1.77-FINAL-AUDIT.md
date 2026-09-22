# Weather FX 8.1.77 Final Audit

Build basis: exact Weather FX 8.1.76.

## User-reported defect

Rain could still slow, stop, then resume while walking near a map edge and again when turning around, with WEATHER FRONTS OFF.

## Root causes addressed

1. The validated procedural renderer was not guaranteed to be the active shipping path on every host. Hosts that reject/collapse instancing legitimately fall back to CPU rain, and that fallback still recycled around the live player and still had a camera-forward visibility gate.
2. Procedural rain phase was driven by `simTime`, which advances only through the precipitation update. Short host streaming/turn-state stalls therefore appeared as the entire rain field slowing/freezing even if drawing resumed immediately afterward.
3. Procedural world-anchor cells could sit far enough from the observer that turning toward the opposite side exposed the edge of the configured rain disk.

## Runtime changes

- `lib/voxel_atmos/WorldPrecip.lua`
- `lib/ProceduralPrecipField.lua`

## Corrected contracts

- CPU fallback visible rain is world-anchored and never camera-forward culled.
- CPU particle recycle distance and respawn center use the stable world anchor, not the live avatar position.
- Procedural rain uses a monotonic render clock; CPU rain gets bounded wall-delta catch-up.
- Procedural anchor cells use 4% of weather radius, cap 24, minimum 4.
- Explicit rain OFF and authored transitions remain authoritative.

## Qualification

The new 8.1.77 regression passes 16/16. Exact 8.1.76 fails 9/16 as expected. Inherited precipitation, snow, settings, performance, 3D pipeline, feature, compatibility, revision, and Lua suites listed in the release notes all pass.

## Visual limitation

No fresh live-game framebuffer capture was produced in the tool environment. Final confirmation of the user's exact map-edge/camera-turn presentation remains an in-game host test.
