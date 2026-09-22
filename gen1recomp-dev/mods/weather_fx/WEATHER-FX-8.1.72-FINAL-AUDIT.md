# Weather FX 8.1.72 Final Audit

Build basis: exact Weather FX 8.1.71.

## Intent

Add a player-facing weather-only render-distance control without changing the voxel/world render distance.

## Player-facing behavior

`PRECIPITATION -> 3D WEATHER DISTANCE` exposes 25%, 50%, 75%, and 100%. Default is 100%.

- With WEATHER FRONTS OFF, 100% equals the active Voxel3D far distance exactly.
- 75%, 50%, and 25% shorten the WorldPrecip field to that fraction of voxel far distance.
- The setting never writes to Voxel3D.far or the world renderer.
- WEATHER FRONTS ON keeps the inherited regional/front-owned radius behavior.
- Rain/snow already derive population from covered area; fixed-budget hail/sand/ash/debris now receive the matching area factor under reduced fronts-OFF reach, preventing a density spike.

## Runtime delta

Runtime Lua changed from exact 8.1.71:

- `lib/Settings.lua`
- `lib/voxel_atmos/WorldPrecip.lua`

Release metadata also updates `manifest.json` / `BASELINE` to 8.1.72 and adds release documentation/tests.

## Executable qualification

- New 8.1.72 weather-distance regression: 16 passed / 0 failed.
- Exact 8.1.71 negative control: 12 failures, proving the new setting is not already present in the baseline.
- Inherited fronts-off exact-distance regression: 9/9.
- Inherited fronts-off world precipitation regression: 9/9.
- Procedural instancing validation (snow-fountain/hail-tube fail-open): 6/6.
- World-space precipitation: 33/33.
- Quality immediate 3D: 5/5.
- Quality live 3D: 13/13.
- Precipitation virtualization: 23/23.
- Snow virtualization: 10/10.
- MAX precipitation virtualization: 8/8.
- Snow accumulation setting: 13/13.
- Snow point-plume regression: 9/9.
- Settings runtime: 672/672.
- Settings menu: 32/32.
- Complete player settings interaction audit: 2091/2091.
- Performance invariants: 66/66.
- 3D pipeline integrity: 117/117.
- Feature integrity: 505/505.
- `test_mod --lua`: 191/191.
- Aggressive compatibility: PASS, no HIGH findings.
- Revision gate: 80/80.

## Preserved fixes

8.1.71 exact voxel-distance matching remains the 100% default behavior. 8.1.70 procedural instance-collapse protection for the snow fountain/hail tube and 8.1.69 SNOW ACCUMULATION ON/OFF remain active.
