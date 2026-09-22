# Weather FX 8.1.80 Final Audit

## Baseline

Exact source baseline: Weather FX 8.1.79.

## Runtime delta

Runtime code delta is exactly one file:

- `lib/voxel_atmos/CinematicAtmos.lua`

Non-runtime release changes:

- `manifest.json` version/baseline note;
- `tests/performance_frame_reuse_8180_test.lua`;
- `tools/run_all.py` registers the current 8.1.80 regression first;
- 8.1.80 release/audit/qualification documents.

## Safety review

The optimization deliberately does not introduce an unprotected fast path. Host calls remain behind the existing `V.safeCall` compatibility boundary. The frame-spatial cache is refreshed once at the start of every `CinematicAtmos.draw`, before atmospheric subpasses. Existing helper functions retain their legacy calculation path when no matching frame cache exists.

Sequential vertex-map caching is safe because the six affected passes build the same conventional quad index sequence via `pushQuad`: index content is a pure function of the index count. The cache invalidates on either Mesh identity or index-count change. Vertex positions/attributes continue to use `Mesh:setVertices` every frame, so no weather motion or current geometry is frozen.

Uniform scratch tables are populated immediately before `Shader:send`; only transient Lua table allocation is removed. The arithmetic expressions that produce shader values are preserved.

## Quality-preservation checks

- Rain 12,000 cap unchanged.
- Hail 45,000 cap unchanged.
- Snow 100,000 base cap unchanged.
- Landscape weather-cell frustum test unchanged.
- Exact rendered-world fronts-OFF precipitation rules inherited from 8.1.78 remain green.
- No settings or assets changed.

## Test results

- Current release regression: 29/29 PASS.
- Negative control on exact 8.1.79: expected FAIL (23 new checks fail).
- Revision gate: 80/80 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline: 117/117 PASS.
- Feature audit: 505/505 PASS.
- Voxel host contract: 27/27 PASS.
- Sandbox: 125 runtime files PASS.
- Maintained Lua release suite: 191/191 PASS.
- Runtime Lua compiler: 125/125 PASS.

The large historical `run_all.py --lua` chain contains version-scoped snapshot tests from superseded releases that are expected to fail on later versions; the maintained current gates above are the release authority used for 8.1.80.

## Visual qualification

No new look is intended. No live framebuffer capture was available in this environment, so no claim of live visual inspection is made. A low-power-device frame-time comparison against 8.1.79 is recommended for empirical FPS/frame-pacing measurement.
