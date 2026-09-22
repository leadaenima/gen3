# Weather FX 8.1.47 — Flat-Voxel Zero-Quality-Loss Performance Audit

## Scope

This audit compares exact Weather FX 8.1.46 against 8.1.47. The goal is to remove CPU/GC/resident-state work that does not contribute to the current voxel picture. It is **not** a quality reduction release and these isolated timings are **not** whole-game FPS claims.

## Frozen visible-runtime preservation

The 8.1.47 runtime delta is restricted to seven infrastructure modules:

- `lib/EngineRuntime.lua`
- `lib/FlatWorldInteraction.lua`
- `lib/GPUWeatherEngine.lua`
- `lib/LightProbeGrid.lua`
- `lib/SurfaceVisuals.lua`
- `lib/VolumetricWeather.lua`
- `lib/WorldStreamer.lua`

The other **154/161 frozen runtime files are byte-identical to 8.1.46**, including the production precipitation, cloud/front, water, celestial, aurora, constellation, snow, leaf, lightning, shadow, audio and gameplay paths.

## Continuous scheduler reduction

`EngineRuntime` scheduled passes: **42 → 38**.

The removed continuous passes are SDK/debug/advisory metadata systems that no current Weather FX renderer consumes:

- WorldStreamer
- GPUWeatherEngine
- LightProbeGrid
- SurfaceVisuals

Their compatibility APIs remain callable and derive state on demand.

`PredictiveBudget` and `WorkloadRouter` remain installed for AUTO PERFORMANCE, but return immediately under fixed manual QUALITY because manual tiers intentionally do not consume their adaptive trims.

## Flat-world footprint cache

The previous `FlatWorldInteraction.sampleAt()` repeatedly recomputed the same static 3×3 shelter neighborhood and 5×5 building/tree/water footprint. 8.1.47 caches that static profile per stable voxel map cell while leaving directional wind shadow live.

Executable old-vs-new equivalence: **21,760/21,760 returned values exactly agree** across ground/building/tree/water cells and five wind directions.

Interpreted `texlua`, 50,000 sample calls, five runs each:

- 8.1.46 median: **337.393 ms**
- 8.1.47 median: **101.266 ms**
- isolated path reduction: **~70.0% CPU time** (~3.33× faster)

This is a module microbenchmark, not an FPS multiplier.

## Volumetric descriptor virtualization

The production renderer consumes aggregate cloud/precipitation/transmission values, not the historical 5×5×3 resident cell table. 8.1.47 computes the exact aggregate equations directly. The public `VolumetricWeather.cells()` API still lazily materializes all **75** detailed cells if an SDK/debug consumer asks for them.

Normal gameplay resident detailed cells: **75 → 0** until requested.

Executable old-vs-new equivalence: **3,648/3,648 aggregate and detailed-cell values exactly agree**.

Interpreted `texlua`, 2,000 updates, five runs each:

- 8.1.46 median: **127.142 ms**
- 8.1.47 median: **66.812 ms**
- isolated module reduction: **~47.5% CPU time**

Again, this is not a whole-game FPS claim.

## Light probe virtualization

The old compatibility grid retained **49** pseudo-probe cells although the voxel renderer never sampled them. 8.1.47 retains the same query formula analytically with **0 resident cells**.

Executable old-vs-new equivalence: **147/147 sampled lighting values exactly agree**.

## Deliberately retained systems

No attempt was made to remove systems with real current visual/gameplay/API authority: StormCells, DistantWeather, MesoscaleField, Microclimate, WorldClimate, WindEngine/WindFlow, Hydrology, EnvironmentSurface, SnowPack, LeafPhysics, Dynamic/Unified lighting, WeatherShadowMap, connected water, precipitation/lightning/audio, atmosphere/celestial/aurora, tornado or rainbow.

That restraint is intentional. 8.1.47 removes only work for which we could prove either non-consumption by the current voxel renderer or exact output equivalence.
