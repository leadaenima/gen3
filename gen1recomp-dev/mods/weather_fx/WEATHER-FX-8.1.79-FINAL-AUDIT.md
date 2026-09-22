# Weather FX 8.1.79 Final Audit

## Scope

Built directly from exact Weather FX 8.1.78. Runtime delta is intentionally limited to:

- `lib/CloudField.lua`
- `lib/Constellations.lua`
- `lib/ProceduralPrecipField.lua`
- `lib/ProceduralSnowField.lua`
- `lib/RenderGraph.lua`
- `lib/SnowSurfacePaint.lua`
- `lib/WeatherShadowMap.lua`
- `lib/voxel_atmos/WorldPrecip.lua`
- `manifest.json` version/baseline note

One new executable regression is added: `tests/performance_cleanup_8179_test.lua`.

`config.lua`, player-facing settings, assets, authored shader source, weather tables and particle/quality budgets are not retuned by 8.1.79.

## Performance cleanup verified

- RenderGraph scheduler metadata/stat references are cached per pass.
- Procedural precipitation uniform vectors are reused.
- WorldPrecip live procedural draw/probe option vectors are reused while preserving LuaJIT closure headroom.
- SnowSurfacePaint removes per-texel protected-call overhead and reuses raster/uniform/matrix scratch.
- WeatherShadowMap removes the redundant second projection fit per recast without introducing light-space snapping or changing resolution selection.
- Constellation traced-star expansion is lazy; first access still produces exactly 8,507 stars.
- CloudField caches update-invariant climate scalars across its 49-cell field.

## Preserved weather/render contracts

- 8.1.78 rendered-world rain coverage remains exact with WEATHER FRONTS OFF.
- 100% 3D WEATHER DISTANCE remains equal to live voxel far distance; lower values only reduce Weather FX reach.
- WEATHER FRONTS ON remains regional/front-owned.
- Rain cap 12,000; hail cap 45,000; base snow cap 100,000 remain unchanged.
- Constellation peak brightness and all 8,507 traced points remain unchanged.
- Shadow projection remains continuous with no rotating-light texel snap.
- Snow surface repaint remains bound to real support geometry.

## Regression results

- 8.1.79 performance cleanup: 25/25 PASS.
- Exact 8.1.78 negative control: 11/25 PASS, 14/25 FAIL as expected.
- 8.1.78 rendered-world rain: 14/14 PASS.
- 8.1.74 fronts-OFF continuous precipitation: 16/16 PASS.
- 8.1.70 fronts-OFF world precipitation: 9/9 PASS.
- 8.1.73 precipitation streaming: 12/12 PASS.
- world-space precipitation: 33/33 PASS.
- precipitation virtualization: 23/23 PASS.
- near virtualization: 17/17 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- snow surface repaint: 24/24 PASS.
- weather shadow engine: 26/26 PASS.
- shadow projection monotonicity: 11/11 PASS, Weather FX reversals 0.
- continuous celestial/shadow motion: 42/42 PASS.
- expanded constellations: 65/65 PASS.
- constellation peak brightness: 34,110/34,110 PASS; 8,507 stars.
- cloud sun localization: 10/10 PASS.
- storm cloud-bank integration: 13/13 PASS.
- front audio/motion/cloud: 15/15 PASS.
- revision gate: 80/80 PASS.
- performance invariants: 66/66 PASS.
- 3D pipeline integrity: 117/117 PASS.
- feature integrity: 505/505 PASS.
- LuaJIT direct-upvalue estimate for `WorldPrecip.update`: 51, shipping threshold 55, hard limit 60 — PASS.
- `test_mod.py --lua`: 191/191 PASS.

## Visual evidence

No fresh live-game framebuffer was generated in this environment. This audit does not claim a host framebuffer or visual play session that was not actually captured.
