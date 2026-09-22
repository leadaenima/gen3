# Weather FX 5.0 Engine Architecture

## Goals

1. One authoritative owner for each simulation/render responsibility.
2. Keep expensive work local to active world regions.
3. Reuse allocations and GPU buffers instead of rebuilding them each frame.
4. Make advanced visuals scalable by quality tier without deleting core world content.
5. Fail open on unsupported host capabilities and never patch another mod on disk.

## Runtime graph

`EngineRuntime` executes seven ordered stages:

`world → climate → celestial → environment → presentation → effects → audio`

`RenderGraph` sorts passes by priority and prevents two owners from claiming the same critical resource. The benchmark hook can still insert an authoritative weather override immediately after climate and before all downstream consumers.

## Allocation / spatial systems

- `ObjectPool`: reusable tables/records with bounded free lists.
- `SpatialIndex`: uniform-grid radius/nearest queries using pooled records.
- `ChunkSim`: sparse active/sleeping world chunks; empty distant chunks can disappear while non-empty environmental state persists.
- `EnvironmentSurface`: sparse wet/snow/leaves/scorch/ice/temperature state on top of ChunkSim.

## GPU particle path

`ParticleBatcher` owns reusable high-water mesh capacity and capability detection. WorldPrecip attempts this central upload path and falls back to its mature local uploader if a host rejects it. This keeps compatibility while allowing more particle families to migrate to shared batching incrementally. Existing SpriteBatch/VBO pools remain valid.

## Weather / atmosphere

`WeatherState` remains the authored weather ID/rule authority. `WeatherSimulation` derives continuous meteorological variables from it; `WorldClimate` supplies bounded coarse regional memory; 8.0.8 `MesoscaleField` reconstructs moving O(1) moisture/front bands between the coarse grid and local `Microclimate`; `AtmosphereModel` derives scattering/haze/warmth/visibility state. Cloud occupancy, volumetric precipitation, local audio/lightning and GPU far-field precipitation consume this shared spatial state. 3D hosts receive the resulting continuous state through the private Weather FX voxel namespace.

## Celestial ownership

`CelestialRenderer2` is the public Weather FX celestial facade. Strict-3D Dramaless presentation invokes one projected background entry, which owns deep sky and sun/moon fallback ordering. `CelestialEngine` remains the astronomy/optics state authority; `NightSky` remains the geometry catalogue/renderer.

## Performance policy

POTATO/LOW/MEDIUM/HIGH/MAX reduce expensive simulation/render detail through particle budgets, star stepping, atmosphere budgets and other scalable work. Core content such as the nine planets is not deleted by LOD. MAX authored particle ceilings are unchanged.

## Compatibility policy

All host integration is in-memory and guarded. `HostAdapter` probes capabilities; unsupported centralized paths fall back to the existing tested host-specific implementation. Weather FX does not permanently edit another mod's files.

## Release gates

5.0 requires the legacy revision/runtime/compatibility suite plus:
- `tools/test_engine_architecture.py`
- `tests/engine_architecture_test.lua`
- exact user-drawing constellation gate
- celestial/no-halo/direct-sun gates
- full strict architecture and compatibility audits
- clean-extracted ZIP retest
