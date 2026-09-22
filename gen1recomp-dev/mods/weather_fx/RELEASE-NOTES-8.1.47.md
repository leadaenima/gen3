# Weather FX 8.1.47 — Flat-Voxel Zero-Quality-Loss Runtime Pruning

## Goal

Reduce CPU/GC/memory work that does not contribute to the current voxel picture **without reducing any graphics or changing authored weather behavior**. This release is built directly from exact 8.1.46 and keeps 8.1.46 as the rollback baseline.

## Continuous runtime work removed

Four compatibility/advisory systems were still being scheduled during ordinary gameplay even though no Weather FX 2D/3D renderer consumes them:

- `WorldStreamer` — planning-radius metadata only; it does not stream Voxel Nexus or Weather FX geometry.
- `GPUWeatherEngine` — advisory budget metadata only; actual precipitation GPU/CPU ownership remains in `WorldPrecip` / procedural fields.
- `LightProbeGrid` — the real voxel lighting path never samples its 7x7 pseudo-probe grid.
- `SurfaceVisuals` — summary metadata only; actual puddle/snow/leaf/wet rendering consumes `SurfaceVisualState` and the dedicated renderers.

They remain available through the existing exported SDK/debug functions. Their values are now derived on demand instead of maintained continuously.

## Exact flat-world cache

`FlatWorldInteraction.sampleAt()` previously re-walked the same static 3x3 neighbourhood and 5x5 footprint for every WindFlow/Hydrology sample even though the underlying voxel-map classification cache had not changed. 8.1.47 caches that static profile per stable map cell. Directional wind shadow still updates from the live wind vector.

An old-vs-new executable comparison checked **21,760 returned values** across ground, buildings, trees, water and five wind directions with exact agreement. A 50,000-sample interpreted-Lua microbenchmark measured five-run median **337.4 ms → 101.3 ms** in this isolated path (~3.33x faster / ~70.0% less CPU time). This is an isolated CPU benchmark, not a whole-game FPS claim.

## Volumetric descriptor virtualization

The production voxel renderer consumes only aggregate `cloudVolume`, `precipVolume`, `lightTransmission`, `farPrecipScale` and `shadowScale`; it never consumes the resident 5x5x3 table. 8.1.47 computes the exact same aggregate equations without retaining 75 Lua cell tables or calculating/storing per-cell electrical charge on normal gameplay frames.

The public `VolumetricWeather.cells()` API still materializes the full 75-cell table when a companion/debug consumer explicitly requests it. An executable old-vs-new comparison checked **3,648 aggregate and materialized-cell values** with exact agreement. A 2,000-update interpreted-Lua microbenchmark measured five-run median **127.1 ms → 66.8 ms** for this isolated module (~47.5% less CPU time).

## Manual-quality bookkeeping

`PredictiveBudget` and `WorkloadRouter` only influence AUTO PERFORMANCE. Fixed manual quality tiers intentionally ignore their trims, so 8.1.47 stops running those calculations while manual QUALITY is selected. AUTO behavior is unchanged.

## What was intentionally NOT removed

Real flat-world systems remain live: `StormCells`, `DistantWeather`, `MesoscaleField`, `Microclimate`, `WindEngine`, `WindFlow`, `Hydrology`, `EnvironmentSurface`, `SnowPack`, `LeafPhysics`, `WeatherShadowMap`, atmosphere/celestial/aurora, tornado/rainbow, connected water and all precipitation/lightning/audio paths. Several of these use real building/tree/water footprints and therefore are useful specifically in a flat voxel world.

## Preservation contract

No particle ceiling, texture, shader, cloud/front geometry, water/reflection quality, celestial catalogue, constellation geometry/brightness, aurora geometry, snow/leaf population, weather timing, gameplay hook or audio asset is reduced. Runtime changes from exact 8.1.46 are limited to:

- `lib/EngineRuntime.lua`
- `lib/FlatWorldInteraction.lua`
- `lib/GPUWeatherEngine.lua`
- `lib/LightProbeGrid.lua`
- `lib/SurfaceVisuals.lua`
- `lib/VolumetricWeather.lua`
- `lib/WorldStreamer.lua`

Everything else in the frozen runtime must remain byte-identical to 8.1.46.
