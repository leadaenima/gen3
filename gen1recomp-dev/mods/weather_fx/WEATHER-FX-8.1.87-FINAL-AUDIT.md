# Weather FX 8.1.87 — Final Audit

Built directly from exact Weather FX 8.1.86.

## Runtime changes

Exactly two runtime Lua files differ from 8.1.86:

1. `lib/voxel_atmos/CinematicAtmos.lua`
   - RAVE laser emitters are generated from a deterministic world/cloud lattice instead of the camera-filtered visible-cloud list.
   - Beam centerlines are camera-independent; the camera is used only to expand an existing centerline into a view-facing ribbon.
   - The active field includes overhead/near, mid-distance and far-distance emitters across all horizontal quadrants.

2. `lib/DramalessAtmos.lua`
   - Carries the last proven pre-battle outdoor/sky authority into a 3D/world-backed battle.
   - Prevents transient battle-stack `outdoor=false` reports from killing the entire 3D atmosphere frame.
   - `Battle._startedIndoors` remains authoritative, so caves/buildings do not inherit outdoor precipitation.

No other runtime Lua file changes.

## New regression evidence

- RAVE world-space laser regression: 10/10 PASS.
- 3D battle weather persistence regression: 13/13 PASS.
- Negative control on exact 8.1.86:
  - RAVE laser regression: 2 PASS / 8 FAIL.
  - Battle persistence regression: 6 PASS / 7 FAIL.
- Full 8.1.87 source developer sweep: 88/88 programs PASS.
- Runtime Lua source compilation: 123/123 PASS.

## Scope

This audit proves executable logic, integration contracts and package integrity. No fresh live-game framebuffer/device session was available, so it does not claim a manual visual playtest.
