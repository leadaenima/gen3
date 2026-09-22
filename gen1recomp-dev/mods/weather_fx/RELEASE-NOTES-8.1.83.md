# Weather FX 8.1.83 — Full Developer Sweep / Weather Ownership Repair

Built directly from exact Weather FX 8.1.82.

## Repairs

- **3D snow smoothness:** procedural snow now uses a monotonic presentation clock, decoupling visible fall motion from uneven simulation update chunks while preserving authored fall-speed and wind equations.
- **Fronts-OFF hail coverage:** virtualized hail keeps its tiny CPU interaction/probe radius but uses the full configured visual/render radius on an absolute rendered-world grid.
- **Fronts-OFF sand/dust coverage:** sand and dust no longer orbit the player in a tight local column; procedural visual ownership spans the rendered weather distance.
- **Fronts-OFF ash / black-ash coverage:** ash's grey/dark variants use the same full rendered-world field instead of a player-local column.
- **2D weather in 3D battles:** nonopaque/world-backed voxel battles are now 3D-owned across precipitation, grains, fog and lightning. Opaque/classic battles keep their dedicated 2D compositor.
- **Battle weather handoff:** BattleDraw's battle-owned channels continue easing under 3D ownership and are published to the 3D atmosphere, so Rain Dance/Hail/Sandstorm-style battle changes do not freeze on overworld weather.
- **WEATHER OFF reversibility:** a newer player menu choice is reconciled into the engine weather ladder before WeatherState/runtime consumption so a stale OFF rung cannot overwrite the player's re-enable request.
- **Sun glare/god rays:** direct-look optics now prefer a real host camera-forward vector or FirstPerson yaw/pitch instead of assuming `eye -> focus` is camera direction; a basis projection fallback covers hosts whose VP format cannot be decoded.

## Preserved contracts

No particle ceiling, visual density, configured weather distance, water/wind behavior, tornado cloud descent, tornado pickup/safety behavior, quality ceiling, asset, or authored animation rate is reduced. WEATHER FRONTS ON remains regional/front-owned.

## Developer sweep

The repeatable `tools/developer_sweep_8183.py` matrix passes **83/83 programs**. Release-specific `feature_integrity_8183_test.lua` passes **49/49** and fails **42/49** checks on exact 8.1.82 (7 pass / 42 fail), proving the new protections are not inherited false positives. Current major gates include: 2D weather style 94/94, world-space precipitation 33/33, fronts-OFF render distance 9/9, snow motion 10/10, world lightning 493/493, 3D tornado 38/38, celestial engine 49/49, celestial occlusion 10/10, settings runtime 731/731, complete player-setting interaction 2226/2226, 3D pipeline 117/117, feature integrity 505/505, revision 80/80, performance invariants 66/66, voxel-host compatibility 27/27, maintained Lua 191/191, and 125/125 shipped runtime Lua compile.

## Visual qualification

This environment did not provide a fresh live-game framebuffer/device session. The release is qualified by exact executable/static harnesses and package replay; no claim of new manual in-game visual inspection or measured FPS is made.
