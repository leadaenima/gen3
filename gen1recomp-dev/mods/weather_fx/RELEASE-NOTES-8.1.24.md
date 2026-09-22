# Weather FX 8.1.24 — Zero-Quality-Loss Performance Architecture

## Goal
Make Weather FX smoother and cheaper to run without changing what the player sees or how weather behaves. This release contains no particle-count, cloud-count, celestial-count, quality, draw-distance, shadow-quality, storm-coverage, or timing reductions.

## CPU / GC work removed
- **WeatherState:** frame-constant rain/snow/fog/sand/dust/wind/storm-darkness controls are read once per update instead of per amount channel; AUTO-family scaling reuses a scratch table.
- **WorldClimate:** 121 active cells reuse one target scratch and nine smoothing coefficients per update instead of allocating target tables and recomputing identical exponential factors per cell.
- **Microclimate:** map/target scratch structures are reused.
- **WindFlow:** 9×9 cells use numeric grids and cache deterministic noise/turn coefficients; stable module resolutions are reused.
- **Hydrology:** 9×9 cells cache deterministic basin/elevation and use object-keyed runoff deltas instead of string-cell churn.
- **LightProbeGrid:** 7×7 probes cache deterministic occlusion coefficients.
- **CloudField:** 7×7 cells cache deterministic charge noise, numeric cell identity and successful MesoscaleField resolution.
- **StormCells:** lifecycle amplitude/radius/stage coefficients are prepared once per cell update and reused by spatial samples.
- **EngineRuntime:** mesoscale, volumetric and severe-weather consumers share the same exact center WorldClimate reference in a frame; a redundant third surface-state sample was removed.
- **MesoscaleField:** the Weather FX Types module is bound outside the high-frequency spatial sample path instead of protected-required for each sample.
- **Night sky:** procedural planet surface topology/colors, Saturn/Planet-X ring topology, projected ring arcs, and the 220-point Milky Way base geometry are immutable caches. Constellation static billboard size is cached and a redundant per-star fade dispatch is removed; the full approved traced catalogue remains.
- **Cloud occlusion / god rays:** each live cloud descriptor caches its invariant rotation and body spans once for that frame instead of recomputing them at every ray/cloud intersection.

## Preserved player experience
- RAIN_MAX remains 12,000; SNOW_MAX remains 100,000; HAIL_MAX remains 45,000 and all other authored/quality particle ceilings remain intact.
- Full 5,120-star ordinary catalogue and the approved constellation catalogue remain intact.
- CloudField radius, StormCell maximum count/size/lifecycle, moving cross-map fronts and localized edges remain intact.
- CLOUD HEIGHT RAISED/ORIGINAL and WEATHER FRONTS full-map fallback behave exactly as in 8.1.23.
- WEATHER DURATION remains lifetime-only. Particle velocities, wind/cloud advection, audio, celestial/game time, lightning cadence and transition-animation speed are unchanged.
- WeatherShadowMap behavior and quality are unchanged.

## Validation philosophy
A specific game-FPS percentage is not claimed from headless tests. The release proves numerical/semantic equivalence and algorithmic work removal; final device FPS depends on Gen1Recomp/LÖVE host, GPU, CPU and other mods.
