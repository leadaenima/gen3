# Weather FX 8.1.76 — Rain Ledge Continuity / Water-Streak Model

## What changed

- Fronts-OFF rain drawing now follows the stream state that `WorldPrecip.update()` actually allocated. A transient frame-local weather bag can no longer hide one frame of otherwise-active rain.
- Fronts-OFF rain identity is repaired from the explicit WEATHER selection or root Weather FX id when no authored transition is active, preventing pose/elevation frames from briefly reclassifying an active rainstorm as CLEAR.
- Procedural rain uses a stable padded lower fall boundary for the whole rain episode/map. Hopping a ledge no longer changes the fall-column height for every rain instance simultaneously.
- 3D rain has a new water-streak model: thinner and longer geometry, tapered width, feathered head/tail, a narrow light-catching core, lower alpha, and blue-grey water tint. The CPU fallback matches the same profile.

## Preserved

- WEATHER FRONTS OFF remains continuous and uniform across the effective 3D WEATHER DISTANCE.
- 3D WEATHER DISTANCE still only reduces Weather FX reach; 100% still equals the voxel render distance.
- Map-entry precipitation reprime, SnowPack distance matching, snow/blizzard fountain protection, hail-tube instancing validation, and SNOW ACCUMULATION ON/OFF remain unchanged.

## Qualification

- New rain ledge/draw/model regression: 14/14 PASS.
- Exact 8.1.75 negative control: 3 PASS / 11 FAIL (expected).
- Inherited rain walking regression: 12/12 PASS.
- Fronts-OFF continuous precipitation: 16/16 PASS.
- Precipitation streaming/map-entry: 12/12 PASS.
- 3D weather-distance setting: 16/16 PASS.
- Fronts-OFF world precipitation: 9/9 PASS.
- Procedural instancing validation: 6/6 PASS.
- World-space precipitation: 33/33 PASS.
- Rain/cloud-bank visibility: 9/9 PASS.
- Near precipitation virtualization: 17/17 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- Precipitation virtualization: 23/23 PASS.
- Performance invariants: 66/66 PASS.
- Feature integrity: 505/505 PASS.
- Aggressive compatibility: 30 PASS / 0 MED / 0 HIGH.
- LuaJIT WorldPrecip.update guard: PASS at 51 direct upvalues.
- `tools/test_mod.py --lua`: 191/191 PASS.

No fresh live-game framebuffer capture was produced for this release. The new rain silhouette was analytically rasterized from the shipped mask for shape review, but final visual confirmation on the user's graphics host remains necessary.
