# Weather FX 8.1.83 — Final Developer Audit

## Baseline

Exact source baseline: Weather FX 8.1.82.

## Intentional runtime delta

Eight runtime Lua files change:

- `main.lua`
- `lib/Settings.lua`
- `lib/Battle.lua`
- `lib/BattleDraw.lua`
- `lib/Draw.lua`
- `lib/DramalessAtmos.lua`
- `lib/ProceduralPrecipField.lua`
- `lib/voxel_atmos/WorldPrecip.lua`

Tests/tools/release metadata also change to add the 8.1.83 developer-sweep gate and modernize stale static assertions.

## Root-cause findings and repairs

### Hail / sand / ash rendered distance

8.1.82 correctly collapsed noninteractive GPU-virtualized grain simulation to a 4-unit CPU radius, but the procedural draw path reused that simulation radius as the visual `farRadius`. The result was an overhead/player-local column. 8.1.83 stores `grain.visualRadius` before virtualization and uses it for visible procedural submission. With fronts OFF, hail/sand/ash also select the same absolute rendered-world grid model used by rendered-world rain. Leaves/debris remain physical and are intentionally excluded from world-grid virtualization.

### 3D snow motion

Procedural snow was fed raw `simTime`, so uneven low-power simulation chunks could become visible stepping. 8.1.83 adds `_snowVisualTime()`, a monotonic wall-backed presentation clock equivalent in intent to the existing rain presentation clock. It changes no snow fall coefficient, wind equation, count, or render distance.

### 2D/3D battle ownership

Several Draw ownership gates treated every battle as 2D-only and Battle's overlay painted BattleDraw even when a nonopaque voxel battle was literally showing the 3D world. 8.1.83 distinguishes opaque/classic battles from world-backed battles consistently for precipitation, snow, grains, lightning and fog. Under 3D ownership the overlay does not draw or reset BattleDraw; DramalessAtmos advances BattleDraw once per update and publishes its battle id/channels into the voxel atmosphere.

### WEATHER OFF state

The menu could push OFF to the engine ladder, after which a stale engine/save mirror could overwrite a newer menu request. Settings now keeps a pending player ladder authority and `main.lua` reconciles it before staged runtime/WeatherState consumes the rung. The exact in-menu OFF -> AUTO and OFF -> named-weather path is executable-tested.

### Sun glare

The 3D direct-look calculation still used `eye -> focus`. On several supported voxel hosts, `focus` is the player/world anchor, not a camera target, so the vector can point downward and direct-look alignment cannot occur. 8.1.83 prefers `camera.forward`/`camera.look`, then FirstPerson yaw/pitch, rejects implausible anchor-style focus rays, and retains a conservative horizontal-heading fallback. The actual scene-post glare function is executable-tested: an aligned unobstructed sun produces lens response, 28 radial ray polygons and staged screen wash; SCREEN EFFECTS OFF suppresses only camera optics.

## Full developer sweep

`tools/developer_sweep_8183.py`: **83 programs passed / 0 failed**.

Major direct results:

- 8.1.83 release regression: 49/49
- negative control on exact 8.1.82: 7 PASS / 42 FAIL, expected failure
- weather 2D styles: 94/94
- world precipitation world-space: 33/33
- fronts-OFF render distance: 9/9
- rendered-world rain: 14/14
- snow motion: 10/10
- world lightning: 493/493
- 3D tornado: 38/38
- celestial engine: 49/49
- celestial occlusion/brightness: 10/10
- settings runtime: 731/731
- player setting interactions: 2226/2226
- revision: 80/80
- performance invariants: 66/66
- 3D pipeline: 117/117
- feature integrity: 505/505
- voxel host compatibility: 27/27
- maintained Lua suite: 191/191
- runtime Lua compile: 125/125

## Quality preservation

Rain/hail/snow/blizzard and other authored ceilings are not reduced. 8.1.81 performance optimizations remain. Water physics/wind response, Tornado3D geometry, Weather FX quality policy, weather catalogue, and audio engine are unchanged from exact 8.1.82.

## Limitation

No fresh live framebuffer/device play session was available in this environment. This audit does not claim manual visual proof or device FPS measurements.
