# Weather FX 8.1.51 — Performance Audit

## Scope and baseline

Exact baseline: Weather FX 8.1.50. The release goal is to remove avoidable CPU/GPU-upload/RAM staging pressure introduced by 8.1.50's seamless 3D front particles without lowering any graphics or player-facing behavior.

## Hotspot

The 8.1.50 front-continuity repair correctly replaced painted distant precipitation with individual world-space particles, but its compatibility renderer generated four CPU vertices and four deterministic sine hashes per particle each frame. At MAX, the shared visible-front budget is 9,000 particles. This creates a 36,000-row hydrometeor staging mesh plus 54,000 index values every frame.

## 8.1.51 architecture

`lib/DistantFrontPrecip.lua` provides a LÖVE-instancing path using the already shipped `InstanceSeedBuffer`. Each active front sends only front-level uniforms and instance count. Particle identity, lateral distribution, depth distribution, vertical cycling, wind drift, rain streak size, snow size, blizzard gust/shear and alpha are reconstructed in the shader. The base quad is four indexed static vertices, so instancing does not inflate each particle to six vertex-shader invocations.

`CinematicAtmos._drawDistantWeather` attempts the instanced hydrometeor path first. On success, `_buildDistantWeather(..., true)` continues to build only fog and lightning. On any unsupported/failed instancing path, `_buildDistantWeather(..., false)` executes the preserved 8.1.50 CPU hydrometeor implementation.

The steady state reuses:
- one base mesh;
- the shared immutable 8,192-entry instance seed mesh;
- one shader;
- tiny uniform vector scratch records;
- up to four per-front option records.

After initialization it does not rerun graphics-capability/resource probes, and the skip path does not create CPU hydrometeor hash/quad closures or make a second Quality budget query.

## Quantitative workload accounting

For 9,000 remote particles, the retired supported-host CPU staging path represents 36,000 vertex rows, 252,000 float components (1,008,000 bytes of float payload), 54,000 index values, and 36,000 deterministic sine hashes per frame. The new supported-host CPU path submits front-level uniforms and instanced draws instead.

Controlled two-front benchmark, 80 loops, three independent runs:

| Run | 8.1.50-style CPU particle builder | 8.1.51 instanced CPU preparation | Reduction |
|---|---:|---:|---:|
| 1 | 1.746663 s | 0.000713 s | 99.96% |
| 2 | 1.798171 s | 0.000473 s | 99.97% |
| 3 | 1.966378 s | 0.000473 s | 99.98% |

These numbers isolate CPU-side remote-front preparation. They do not claim a physical-GPU FPS multiplier. GPU-side improvement claimed by architecture is narrower and directly observable from the submission model: no per-frame 36,000-row hydrometeor vertex buffer rebuild/upload, no per-frame hydrometeor vertex-map rebuild, and a four-vertex indexed base rather than a six-vertex non-indexed instancing quad. Shader ALU still renders the same visual population.

## RAM / VRAM behavior

The old CPU stream retained/reused tens of thousands of Lua row records after reaching a dense front. Once the instanced path owns hydrometeors, the builder truncates those rows because only fog/lightning remain. The new renderer adds no per-particle dynamic instance buffer: it shares Weather FX's existing 8,192-float seed buffer and uses a four-vertex base mesh. No new large texture/canvas/residency pool is introduced.

## Max-settings stress

`tests/max_settings_simultaneous_8151_test.lua` supplies all 68 player controls simultaneously through the real `Settings` reader. The profile selects the value that maximizes actual render/simulation workload; notably PARTICLE LIMIT uses TIER because MAX quality's authored snow/blizzard ceilings exceed the numeric 20k override. The stress proves manual MAX remains scale 1.0 under severe sustained frame-pressure simulation and preserves complete weather/celestial caps.

## Quality-preservation gates

- 8.1.50 front continuity: 9/9 PASS.
- 8.1.51 instanced front renderer: 10/10 PASS.
- 8.1.51 simultaneous max settings: 10/10 PASS.
- 8.1.51 performance release static/runtime contract: 18/18 PASS.
- 8.0.1 performance/regression gate: 42/42 PASS.
- 8.0.2 procedural performance/regression gate: 31/31 PASS.

Additional inherited release-wall results are recorded in the final audit/validation after package freeze.
