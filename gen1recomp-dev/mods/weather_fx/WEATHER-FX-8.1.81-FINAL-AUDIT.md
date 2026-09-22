# Weather FX 8.1.81 Final Audit

## Baseline

Exact source baseline: Weather FX 8.1.80.

## Runtime delta

Runtime code changes are limited to:

- `lib/voxel_atmos/Tornado3D.lua`
- `lib/voxel_atmos/ConnectedWater3D.lua`
- `lib/ParticleBatcher.lua`
- `lib/voxel_atmos/Rainbow3D.lua`
- `lib/NightSky.lua`
- `lib/WeatherShadowMap.lua`

Release/test metadata also changes `manifest.json`, `BASELINE`, `BASELINE.md`, `tests/performance_frame_reuse_8180_test.lua`, `tests/resource_efficiency_8181_test.lua`, `tools/run_all.py`, and 8.1.81 release documents. No settings, config, assets, WorldPrecip logic, weather tables or particle-budget definitions change.

## Safety / equivalence review

### Water

Water remains driven by the same live prevailing-wind X/Z inputs and uses the same train/swell/bend equations. The optimization changes loop mechanics and conditional clamp evaluation only. A deterministic reference sample and 300,000-sample checksum match exact 8.1.80. The GPU water-deformation rewrite is intentionally not included because cross-host reflection/shoreline equivalence requires live framebuffer proof.

### Tornado

Tornado formation still derives its top from the live cloud deck and grows downward using the inherited formation formula. Persistent rows replace transient row tables; scalar emission preserves the exact numeric vertex stream. Full land and waterspout differential dumps against exact 8.1.80 have max absolute delta 0.0. Existing tornado/waterspout regressions pass.

### GPU resources

Dynamic mesh growth creates the replacement first and then explicitly releases the superseded GPU object. This reduces overlap lifetime without changing capacity admission or current draw data. CPU-side ImageData is released only after the GPU image copy is created.

### Shadows

Only duplicate uniform sends are suppressed. Any state transition still sends the same shader value, and non-nil model matrices remain conservative to avoid caching mutable host matrices.

## Quality preservation

- rain 12,000 unchanged;
- hail 45,000 unchanged;
- base snow 100,000 unchanged;
- exact fronts-OFF render-distance ownership green;
- wind-driven water preserved;
- tornado cloud descent/attachment preserved;
- shadow quality/resolution unchanged;
- settings/assets unchanged.

## Test results

- Current resource regression: 26/26 PASS.
- Required negative control on exact 8.1.80: expected FAIL, 14 checks fail.
- Tornado 3D: 38/38 PASS.
- Waterspout: 5/5 PASS.
- Remote tornado culling/re-entry: 4/4 PASS.
- Revision gate: 80/80 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline: 117/117 PASS.
- Feature audit: 505/505 PASS.
- Voxel-host contract: 27/27 PASS.
- Sandbox: 125 runtime Lua files PASS.
- Maintained Lua suite: 191/191 PASS.
- Runtime Lua compiler: 125/125 PASS.
- Inherited rendered-world rain/front/distance suite: PASS.

The historical `run_all.py --lua` chain exposes two known stale 8.1.51 snapshot assumptions that reproduce identically on exact 8.1.80; they are not regressions from 8.1.81. Current `tools/test_settings_runtime.py`, `tests/settings_runtime_test.lua`, and `tests/player_settings_8149_complete_test.lua` are green.

## Benchmark scope

The included performance proof is an isolated deterministic renderer/kernel benchmark. It proves lower local CPU/allocation cost and exact numeric output; it is not a whole-game, device-FPS or power-consumption measurement.

## Visual qualification

No fresh live framebuffer capture is available in this environment. No claim of human in-game visual inspection is made for 8.1.81.
