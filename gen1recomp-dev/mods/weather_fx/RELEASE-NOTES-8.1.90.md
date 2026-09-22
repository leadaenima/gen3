# Weather FX 8.1.90 — Feature-Aware Runtime + Full RAVE Atmosphere

Built directly from exact Weather FX 8.1.89.

## What changed

### Feature-aware 2D/3D runtime ownership
Weather presentation is no longer treated as one blunt 2D/3D switch. Pure 2D configurations stop background 3D work that has no enabled consumer, while strict 3D releases unused 2D particle/NPC-lightning working sets. Individually selected 3D features remain independent: 2D rain/snow can still run under 3D cloud banks, with 3D celestials and enhanced 3D water enabled independently. Shared weather state, time/day-night, seasons, lightning timing/audio, and gameplay authority remain available where required.

### BLOCKY cloud reconstruction
The BLOCKY 3D cloud style now uses connected stepped strips that form one coherent pixel/block cloud silhouette instead of a visible grid of small cubes. Weather coverage, altitude, fronts, wind advection, precipitation origins, and cloud ownership are unchanged.

### 3D snow-fountain repair
Visible snow no longer uses the secondary near-field instanced backend that could collapse valid world positions into a narrow vertical fountain on some drivers. Dense snow remains on the proven procedural GPU field; unsupported/smaller populations use explicit world-XYZ CPU cards. Stale distant snow/blizzard slabs are also retired when authoritative local snow is already active.

### Full RAVE atmosphere
RAVE remains manual-only and carries no rain/snow/hail/sand/ash mechanics. Its existing 128-BPM clock now drives a coordinated 16-beat show: fan sweeps, opposing cross sweeps, rotating room sweeps, and beat-quantized drop/strobe sections. Every beam has a broad atmospheric halo plus a crisp depth-tested core. A bounded field of rolling 3D fog now occupies the local world. Each fog body tests the live laser centerlines; while a laser intersects it, that fog body changes to the exact laser color and returns to neutral haze immediately after the beam leaves. Moving-head targets also paint soft additive depth-tested color pools onto the ground, so the beams visibly land in the world instead of ending invisibly. A master show cue slowly washes the authored RAVE sky and atmospheric ray palette through the same phrase clock, while volumetric and BLOCKY cloud styles retain synchronized hue motion.

## Validation
- 88/88 maintained Lua programs PASS.
- `rave_show_8190_test.lua`: 22/22 PASS.
- `feature_aware_gating_8190_test.lua`: 17/17 PASS.
- `block_cloud_coherence_8190_test.lua`: 6/6 PASS.
- `snow_fountain_guard_8190_test.lua`: 9/9 PASS.
- Aggregate `tools/test_mod.py --lua`: 192 passed, 0 failed, 0 skipped.
- Settings runtime: 269/269 PASS.
- Revision gate: 80/80 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline integrity: 117/117 PASS.
- Voxel-host compatibility: 27/27 PASS.
- Feature audit: 508/508 PASS.
- Love sandbox: 128 shipped runtime Lua files PASS.

No fresh live-game framebuffer/device session was captured for 8.1.90. The visual changes therefore still require real-host eyes-on confirmation.
