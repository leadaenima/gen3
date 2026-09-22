# Weather FX 8.1.92 Final Audit

## Scope

Built directly from exact Weather FX 8.1.91. Runtime change is intentionally narrow: `lib/voxel_atmos/WorldPrecip.lua`. The 8.1.91 Battle Art water repair is not modified.

## Snow coverage correction

- Fronts ON no longer clamps falling 3D snow to `SNOW_RADIUS_MAX` / 750 world units.
- At the default 100% weather distance, `SNOW_STREAM_RADIUS` is the live voxel far distance.
- 25/50/75% remain explicit player-selected reductions and work in either fronts mode.
- Snow procedural preflight resolves the same snow-specific far radius before the first proven GPU draw.
- Front patchiness/density behavior remains available; rain/hail regional radii remain unchanged.

## Automated evidence

- `tests/snow_render_distance_8192_test.lua`: 8/8 PASS.
- Exact 8.1.91 negative control against that regression: 2/8 PASS, 6/8 FAIL.
- Updated inherited 8.1.70/8.1.71/8.1.72 render-distance contracts: PASS.
- `tools/developer_sweep_8192.py`: 102/102 programs PASS.

## Limitation

No fresh real-host framebuffer/device session was captured here. Automated/runtime-stub evidence proves the radius ownership and compatibility contracts, but the user's Battle Art setup remains the final visual confirmation.
