# Weather FX 8.1.80 — Frame-Spatial Reuse

Built directly from the frozen Weather FX 8.1.79 source checkpoint.

## Goal

Reduce CPU overhead, transient garbage, repeated host queries and redundant driver work on low-power devices without lowering any visual setting, authored particle population, weather distance, cloud geometry, shadow quality or weather behavior.

## Runtime changes

Only `lib/voxel_atmos/CinematicAtmos.lua` changes at runtime.

- Adds one reusable frame-spatial snapshot for the 3D atmosphere renderer.
  - viewport aspect is queried once per Weather FX draw instead of independently by multiple fog/cloud passes;
  - horizontal camera basis, billboard basis and weather-field forward basis are normalized once and reused;
  - the default world precipitation/cloud-streaming anchor is sampled once and reused by weather-cell traversal.
- Removes the temporary cloud-space focus table from every `eachWeatherCell` traversal; scalar X/Z coordinates are used instead.
- Adds persistent shader-uniform scratch vectors for curve, fog/mist colour, rain colour, cloud colour, sun projection, shear, body direction and common fallback vectors/matrices.
- Caches sequential quad vertex maps for six streamed atmosphere passes: mist, rolling fog, atmospheric particles, fallback rain, volumetric rays and distant weather.
  - vertex rows are still uploaded every frame exactly as before;
  - the index map is resent only when the backing Mesh changes or the number of indices changes.
- Keeps all protected host/API calls. 8.1.80 does **not** trade stability for speed by bypassing sandbox/compatibility guards.

## Explicitly unchanged

- Rain maximum: 12,000.
- Hail maximum: 45,000.
- Base snow maximum: 100,000; inherited MAX blizzard population remains unchanged.
- WEATHER DISTANCE and fronts-OFF exact rendered-world precipitation rules from 8.1.71–8.1.78.
- Cloud-cell/frustum inclusion formula and cloud-space map-persistence behavior.
- Mist, rolling-fog, cloud, ray, puddle and rain shader math.
- Weather presets, settings, assets, constellation geometry/brightness and shadow resolution.
- All other runtime Lua files are byte-identical to 8.1.79.

## Qualification

- 8.1.80 performance/frame-reuse regression: 29/29 PASS.
- Negative control against exact 8.1.79: 23 of the new 8.1.80 checks fail as required.
- Revision gate: 80/80 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline integrity: 117/117 PASS.
- Feature integrity: 505/505 PASS.
- Voxel-host compatibility contract: 27/27 PASS.
- LÖVE sandbox scan: 125 runtime Lua files PASS.
- Maintained `test_mod --lua`: 191/191 PASS.
- All 125 shipped runtime Lua files compile with `texluac -p`.
- Inherited 8.1.71–8.1.78 precipitation/front/distance regressions used for this change PASS.

No live framebuffer was captured in this environment. This release intentionally avoids visual-algorithm changes; live-device frame-time comparison is still the final performance measurement.
