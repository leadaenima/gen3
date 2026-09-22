# Weather FX 8.1.75 Final Audit

Build basis: exact Weather FX 8.1.74.

## User-reported defect

3D rain still started and stopped as the player walked with WEATHER FRONTS OFF after 8.1.74.

## Root cause

8.1.74 removed player-position mesoscale intensity modulation, but rain still had a population-dependent renderer ownership split. Above 1,200 logical drops, the validated procedural field owned visible rain and stayed world-anchored. Below 1,200 drops, the renderer fell back to the legacy CPU visual pool, whose spawn/recycle origin is the live player position. Short 3D WEATHER DISTANCE values and lower particle budgets therefore still used a player-centred visual stream. A transient zero in the live rain channel could also fully deallocate that low-population stream for a frame.

## Runtime changes

- `lib/voxel_atmos/WorldPrecip.lua`
- `lib/ProceduralPrecipField.lua`

## Corrected contracts

- Fronts-OFF validated procedural rain owns every nonzero visible rain population, including sub-1,200 populations.
- CPU rain after procedural proof is limited to <=96 interaction probes.
- Fronts-ON low-population ownership remains inherited.
- Same-weather fronts-OFF rain survives transient live-channel zeroes through a stable-intensity latch.
- Explicit RAIN AMOUNT OFF remains immediate.
- Authored weather transitions retain normal taper-to-zero behavior.
- Fixed procedural anchors use a tighter cell size so short/medium weather-distance circles do not spend long periods with the player near a large field edge.

## Qualification results

- New rain walking continuity regression: 12/12 PASS.
- Exact 8.1.74 negative control: 5 PASS / 7 FAIL (expected).
- 8.1.74 fronts-OFF uniform precipitation: 16/16 PASS.
- 8.1.73 precipitation streaming/map-entry: 12/12 PASS.
- 8.1.71 exact fronts-OFF voxel distance: 9/9 PASS.
- Precipitation virtualization: 23/23 PASS.
- Near precipitation virtualization: 17/17 PASS.
- MAX precipitation virtualization: 8/8 PASS.
- World-space precipitation: 33/33 PASS.
- Rain/cloud-bank visibility: 9/9 PASS.
- Snow accumulation setting: 13/13 PASS.
- Snow point-plume protection: 9/9 PASS.
- Performance invariants: 66/66 PASS.
- 3D pipeline integrity: 117/117 PASS.
- Feature integrity: 505/505 PASS.
- Aggressive compatibility: 30 PASS / 0 MED / 0 HIGH.
- LuaJIT update upvalue guard: PASS (51 direct upvalues).
- `tools/test_mod.py --lua`: 191/191 PASS.

## Limitation

No fresh live-game framebuffer capture was produced in this pass. The exact low-population/player-walk failure is covered by executable regression and exact-package replay, but final visual confirmation still needs to occur on the user's live graphics host.
