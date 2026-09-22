# Weather FX 8.1.71 Final Qualification

**Status:** qualified for release by exact-distance executable regression plus inherited precipitation, virtualization, quality, performance, feature-integrity and compatibility gates.

## Primary requested behavior

When WEATHER FRONTS is OFF, rain, snow and hail each use the live voxel render distance as their world-field radius. Tests exercised exact radii of 384, 1024, 1536 and 2048 world units. When WEATHER FRONTS is ON, inherited front/quality radii remain active.

## Runtime delta versus exact 8.1.70

Exactly one runtime Lua file changes: `lib/voxel_atmos/WorldPrecip.lua`.

## Key gates

- Fronts-off exact render-distance regression: 9/9.
- Fronts-off 8.1.70 precipitation contract: 9/9.
- Procedural seed-collapse validation: 6/6.
- World-space precipitation: 33/33.
- Immediate 3D quality: 5/5.
- Live 3D quality: 13/13.
- Precip virtualization: 23/23.
- Snow virtualization: 10/10.
- MAX precip virtualization: 8/8.
- Snow accumulation setting: 13/13.
- Snow point-plume regression: 9/9.
- 3D pipeline integrity: 117/117.
- Feature integrity: 505/505.
- Aggressive compatibility: 30 PASS / 0 HIGH.
- MAX performance contract: 5/5.
- Performance/regression static gate: 42/42.

No new live-game framebuffer capture was produced in this pass. The user-provided screenshots motivated the failure mode, while release qualification used executable/runtime contract tests and exact-package replay.
