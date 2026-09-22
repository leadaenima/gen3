# Weather FX 8.1.76 Final Audit

Build basis: exact Weather FX 8.1.75.

## User-reported defects

1. Rain could still start/stop intermittently while walking with WEATHER FRONTS OFF.
2. Hopping ledges could visibly pause rain.
3. The 3D rain model looked like a flat white rectangle rather than rain.

## Root causes

- `WorldPrecip.draw()` independently re-resolved the frame-local weather bag and could suppress rain even after `WorldPrecip.update()` had correctly kept the rain stream allocated. A one-frame CLEAR/zero presentation bag therefore still created a visible gap.
- The procedural rain shader computed fall phase from a bottom boundary tied to current player/focus Y. A ledge hop changed the total fall-column height for every instance simultaneously, causing a field-wide phase jump/pause.
- The procedural rain pixel mask was a softened rectangle and the geometry width/alpha remained too broad/bright.

## Runtime changes

- `lib/voxel_atmos/WorldPrecip.lua`
- `lib/ProceduralPrecipField.lua`

## Corrected contracts

- Update-owned rain allocation is authoritative for the draw pass.
- Fronts-OFF explicit/root rain identity survives transient pose/elevation frame-bag reclassification unless an authored transition or explicit rain OFF is active.
- Procedural rain fall-column bottom is stable across player elevation changes within a rain episode/map.
- New rain geometry is thin and elongated; new mask is tapered, feathered and translucent with restrained blue-grey water tint.
- CPU fallback matches the new rain silhouette.

## Qualification

- New rain ledge/draw/model regression: 14/14 PASS.
- Exact 8.1.75 negative control: 3 PASS / 11 FAIL (expected).
- Rain walk continuity 8.1.75: 12/12 PASS.
- Fronts-OFF continuous precipitation 8.1.74: 16/16 PASS.
- Precipitation streaming 8.1.73: 12/12 PASS.
- Weather render distance 8.1.72: 16/16 PASS.
- Fronts-OFF world precipitation 8.1.70: 9/9 PASS.
- Procedural instancing validation 8.1.70: 6/6 PASS.
- World-space precipitation: 33/33 PASS.
- Rain/cloud-bank visibility: 9/9 PASS.
- Near precipitation virtualization: 17/17 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- Precipitation virtualization: 23/23 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline integrity: PASS.
- Feature integrity: 505/505 PASS.
- Aggressive compatibility: 30 PASS / 0 MED / 0 HIGH.
- LuaJIT update upvalue guard: PASS, 51 direct upvalues.
- `test_mod.py --lua`: 191/191 PASS.

`tests/world_precip_sim_test.lua` did not complete within the isolated 90-second tool timeout and is not counted as a pass.

## Visual limitation

No new live-game framebuffer was captured in the tool environment. The shipped rain-mask formula was rasterized analytically and inspected to verify a tapered streak rather than a rectangle, but the user's real host remains the final visual check.
