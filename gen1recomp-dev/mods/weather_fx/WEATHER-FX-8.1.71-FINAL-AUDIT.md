# Weather FX 8.1.71 Final Audit

Build basis: completed Weather FX 8.1.70 worktree/package.

## Runtime delta

- `lib/voxel_atmos/WorldPrecip.lua`

Documentation/tests/manifest metadata are also updated for 8.1.71. No SnowPack height or accumulation geometry code is changed.

## Exact requested contract

- WEATHER FRONTS OFF: rain radius equals live voxel render distance.
- WEATHER FRONTS OFF: snow radius equals live voxel render distance.
- WEATHER FRONTS OFF: hail radius equals live voxel render distance.
- WEATHER FRONTS ON: inherited regional/front coverage remains unchanged.
- Live voxel render-distance changes are consumed during the current WorldPrecip update.

## Focused executable results

- `fronts_off_render_distance_8171_test.lua`: 9 passed, 0 failed.
- `fronts_off_world_precip_8170_test.lua`: 9 passed, 0 failed.
- `procedural_instancing_validation_8170_test.lua`: 6 passed, 0 failed.
- `world_precip_worldspace_test.lua`: 33 passed, 0 failed.
- `quality_immediate_3d_test.lua`: 5 passed, 0 failed.
- `quality_live_3d_test.lua`: 13 passed, 0 failed.
- `precip_virtualization_test.lua`: 23 passed, 0 failed.
- `snow_virtualization_test.lua`: 10 passed, 0 failed.
- `max_precip_virtualization_8154_test.lua`: 8 passed, 0 failed.
- `snow_accumulation_setting_8169_test.lua`: 13 passed, 0 failed.
- `snow_point_plume_8159_test.lua`: 9 passed, 0 failed.

The legacy monolithic `tools/run_all.py --lua` was also attempted. It ran a large PASS-only inherited prefix but its version-locked 8.1.69 runtime-freeze checks correctly reject newer 8.1.70/8.1.71 runtime files and the overall command exceeded the shell time ceiling. That result is not counted as a pass or a new runtime defect.

## Additional core audits

- Runtime Lua delta versus exact 8.1.70: exactly `lib/voxel_atmos/WorldPrecip.lua`.
- 3D pipeline integrity: 117 passed, 0 failed.
- Feature integrity: 505 passed, 0 failed.
- Aggressive compatibility: 30 PASS, 0 MED, 0 HIGH.
- MAX no-quality-loss performance contract: 5 passed, 0 failed.
- 8.0.1 performance/regression static gate: 42 passed, 0 failed.
