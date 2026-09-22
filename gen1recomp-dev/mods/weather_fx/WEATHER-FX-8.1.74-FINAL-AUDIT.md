# Weather FX 8.1.74 Final Audit

Build basis: exact Weather FX 8.1.73.

## User-reported defect

3D rain was starting and stopping as the player walked, even after 8.1.73 removed player-following precipitation translation.

## Root cause

The precipitation geometry was world-anchored, but `WorldPrecip.update` still multiplied live rain/snow/hail intensity by `MesoscaleField.peek().precipScale`, which is sampled at the player's world position. A dry mesoscale trough could push an otherwise active authored rain channel below WorldPrecip's `> 0.02` allocation threshold. The procedural shaders also still applied mesoscale patchiness while WEATHER FRONTS was OFF.

## Runtime changes

- `lib/voxel_atmos/WorldPrecip.lua`
- `lib/ProceduralPrecipField.lua`
- `lib/ProceduralSnowField.lua`

## Corrected contracts

- WEATHER FRONTS OFF bypasses player-position mesoscale precipitation intensity scaling.
- WEATHER FRONTS OFF sends `uniformField=true` to procedural rain/hail/snow.
- Procedural fronts-OFF mode sends patchiness 0 / floor 1.
- WEATHER FRONTS ON keeps mesoscale banding, but an authored active rain/snow/hail channel cannot be hard-disabled solely by crossing the 0.02 allocation threshold after mesoscale multiplication.
- 8.1.73 fixed world anchors, map reprime, snow accumulation radius, and snow/blizzard fountain protections remain unchanged.

## Qualification results

- New continuous precipitation regression: 16/16 PASS.
- Exact 8.1.73 negative control: 8 PASS / 8 FAIL (expected).
- 8.1.73 precipitation streaming: 12/12 PASS.
- 8.1.72 weather distance: 16/16 PASS.
- 8.1.71 fronts-off exact distance: 9/9 PASS.
- 8.1.70 fronts-off world precipitation: 9/9 PASS.
- Procedural instancing validation: 6/6 PASS.
- Snow point-plume: 9/9 PASS.
- Snow accumulation setting: 13/13 PASS.
- Snow-bank distribution: 13/13 PASS.
- World-space precipitation: 33/33 PASS.
- Rain/cloud-bank visibility: 9/9 PASS.
- Snow motion: 10/10 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- Near precipitation virtualization: 17/17 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline integrity: 117/117 PASS.
- Feature integrity: 505/505 PASS.
- Settings runtime Python: 254/254 PASS.
- Settings runtime Lua: 672/672 PASS.
- LuaJIT upvalue guard: PASS.
- `test_mod.py --lua`: 191/191 PASS.
- Aggressive compatibility: 30 PASS / 0 MED / 0 HIGH.

## Limitation

No fresh live-game framebuffer capture was produced in this build pass. The exact player-walking dropout condition is covered by an executable WorldPrecip regression, but the final visual check still belongs on the user's live graphics host.
