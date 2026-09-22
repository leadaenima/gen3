# Weather FX 8.1.73 Final Audit

Build basis: exact Weather FX 8.1.72.

## User-reported defects addressed

1. Snow accumulation remained in a small circle while the visible weather field extended farther.
2. Snow/blizzard still produced a vertical fountain and sometimes loaded as a tight circle overhead.
3. Weather disappeared on map change until the player moved.
4. 3D rain translated with the player and had lost the more physical streak presentation.

## Runtime changes

- `lib/voxel_atmos/WorldPrecip.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`
- `lib/ProceduralPrecipField.lua`
- `lib/ProceduralSnowField.lua`

## Key contracts

- Accumulation aggregate distribution uses `SNOW_STREAM_RADIUS`, the same effective fronts-OFF 3D weather distance used by visible snow.
- Procedural rain/hail uses fixed world anchors rather than player-relative focus translation, with anchor-cell size adapting downward at short weather distances so the player cannot fall outside the weather disk.
- Live gameplay player coordinates are authoritative on map-entry precipitation anchoring.
- Map changes force re-prime/reanchor in the same update.
- Procedural snow is preflighted before first visible allocation.
- WEATHER FRONTS OFF hard-gates stale distant-front precipitation rendering.
- 8.1.72 3D WEATHER DISTANCE semantics remain unchanged.

## Prepackage results

- New precipitation streaming regression: 12/12 PASS.
- New snow-fountain preflight regression: 4/4 PASS.
- Procedural precipitation field: 10/10 PASS.
- Procedural far snow: 14/14 PASS.
- Procedural instance validation: 6/6 PASS.
- 8.1.72 weather-distance setting: 16/16 PASS.
- 8.1.71 fronts-off exact distance: 9/9 PASS.
- 8.1.70 fronts-off world precipitation: 9/9 PASS.
- World-space precipitation: 33/33 PASS.
- Rain/cloud-bank visibility: 9/9 PASS.
- Snow motion: 10/10 PASS.
- Snow point-plume: 9/9 PASS.
- Snow accumulation setting: 13/13 PASS.
- Snow-bank distribution: 13/13 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- Precipitation virtualization: 23/23 PASS.
- Snow virtualization: 10/10 PASS.
- Settings runtime Python audit: 254/254 PASS after updating its stale 70-setting expectation to the existing 71-setting 8.1.72 schema.
- Settings runtime Lua: 672/672 PASS.
- Settings menu: 32/32 PASS.
- Complete player settings: 2091/2091 PASS.
- `test_mod.py --lua`: 191/191 PASS.
- LuaJIT limit gate: PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline integrity: 117/117 PASS.
- Feature audit: 505/505 PASS.
- Aggressive compatibility: 30 PASS / 0 MED / 0 HIGH.

## Limitation

No fresh live-game framebuffer capture was generated in this pass. The code paths and failure modes are executable-regression qualified, but the user's exact graphics-driver presentation should still be visually checked after install.
