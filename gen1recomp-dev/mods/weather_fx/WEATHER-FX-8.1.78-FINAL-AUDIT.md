# Weather FX 8.1.78 Final Audit

## Scope

Built directly from exact Weather FX 8.1.77. Runtime Lua delta is intentionally limited to `lib/ProceduralPrecipField.lua` and `lib/voxel_atmos/WorldPrecip.lua`.

## New rendered-world rain contract

- WEATHER FRONTS OFF + 100% 3D WEATHER DISTANCE uses the live voxel far distance exactly.
- Procedural rain uses absolute world-grid cells covering the full 2R × 2R voxel render window, not a player/focus-centred disk.
- Absolute cell coordinates own positional jitter, fall phase and personal drift, preserving overlapping rain cells as the render window moves.
- Guard cells prevent dry strips at render-window edges.
- Fronts-OFF rain count budgets square render-window area.
- CPU fallback uses square spawn coverage and a square-safe recycle bound.
- WEATHER FRONTS ON remains regional/front-owned.

## Regression results

- 8.1.78 rendered-world rain: 14/14 PASS.
- Exact 8.1.77 negative control: 4/14 PASS, 10/14 FAIL as expected.
- 8.1.77 map-edge/turn rain: 16/16 PASS.
- 8.1.76 rain ledge/model: 14/14 PASS.
- 8.1.75 rain walk continuity: 12/12 PASS.
- 8.1.74 fronts-OFF continuous precipitation: 16/16 PASS.
- 8.1.73 precipitation streaming: 12/12 PASS.
- 8.1.71 exact fronts-OFF distance: 9/9 PASS.
- 8.1.70 fronts-OFF world precipitation: 9/9 PASS.
- world-space precipitation: 33/33 PASS.
- rain/cloud-bank visibility: 9/9 PASS.
- precipitation virtualization: 23/23 PASS.
- near virtualization: 17/17 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- procedural instancing validation: 6/6 PASS.
- static performance/regression gate: 42/42 PASS.
- 3D pipeline integrity: 117/117 PASS.
- feature integrity: 505/505 PASS.
- aggressive compatibility: 30 PASS / 0 MED / 0 HIGH.
- `test_mod.py --lua`: 191/191 PASS.

## Visual evidence

No fresh live-game framebuffer was generated in this environment. Do not treat executable regression results as a substitute for the user's final host visual test.
