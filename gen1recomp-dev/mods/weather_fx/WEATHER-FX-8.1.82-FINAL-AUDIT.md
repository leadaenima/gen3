# Weather FX 8.1.82 Final Audit

## Baseline

Exact baseline: Weather FX 8.1.81 (`600164a8bc0a7d6930ef6941e3ba6c99bc5241c1e69c3bdb26fdca8103b4b0a4`).

## Runtime changes

Runtime changes are limited to the settings/control paths required for the six requested player capabilities:

- `lib/Settings.lua`
- `lib/Config.lua`
- `lib/Draw.lua`
- `lib/BattleDraw.lua`
- `lib/StormCells.lua`
- `lib/Tornado.lua`
- `lib/NightSky.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`

No precipitation-budget, water-wave, tornado-renderer, wind-engine, weather-distance, asset or quality-ceiling file is changed.

## Behavior preservation

Defaults are exact no-ops versus 8.1.81. Lightning NORMAL is 1.0 cadence, tornado NORMAL is 1.0 mature roam time, cloud NORMAL is 1.0 density / 0 gate bias, night-sky NORMAL is 1.0, screen effects FULL is 1.0, and WET GROUND NORMAL uses the legacy stored token `on` at 1.0 visible strength.

Tornado duration does not scale formation or rope timers. Screen effects do not enter `CinematicAtmos` physical 3D lighting. Cloud density does not replace precipitation authority. Night-sky brightness does not alter sun/moon body shader alpha. WET GROUND amount changes visible puddles/wetness but not precipitation or surface simulation.

## Current gates

- 8.1.82 player settings additions: 50/50 PASS
- settings runtime: 731/731 PASS
- descriptions/completeness: 1,869/1,869 PASS
- live chain: 17/17 PASS
- advanced settings pipeline: 42/42 PASS
- complete player settings interaction: 2,226/2,226 PASS
- current consumer/runtime audit: 267/267 PASS
- simultaneous MAX profile: 10/10 PASS
- inherited 8.1.81 resource efficiency: 26/26 PASS
- inherited 8.1.80 frame reuse: 29/29 PASS
- lightning burst: 24/24 PASS
- world lightning: 493/493 PASS
- storm cell lifecycle: 15/15 PASS
- front audio/motion/cloud: 15/15 PASS
- storm cloud-bank integration: 13/13 PASS
- cloud-bank persistence/pitch: 6/6 PASS
- rain cloud-bank visibility: 9/9 PASS
- tornado 3D: 38/38 PASS
- waterspout: 5/5 PASS
- remote tornado culling: 4/4 PASS
- tornado pickup semantics: 20/20 PASS
- celestial engine: 49/49 PASS
- celestial star field: 7/7 PASS
- host night star spawn: 12/12 PASS
- 8.1.24 night geometry equivalence: 23/23 PASS
- continuous celestial/shadow motion: 42/42 PASS
- celestial zenith projection: 40/40 PASS
- celestial horizon/handoff: 10/10 PASS
- revision gate: 80/80 PASS
- performance invariants: 66/66 PASS
- 3D pipeline: 117/117 PASS
- feature integrity: 505/505 PASS
- voxel host compatibility: 27/27 PASS
- sandbox: 125 runtime Lua files PASS
- LuaJIT guard: PASS
- maintained `test_mod --lua`: 191/191 PASS

## Inherited known test issue

`tests/celestial_occlusion_brightness_test.lua` reports 9 PASS / 1 FAIL on both exact 8.1.81 and 8.1.82 for its static `strict 3D draw has explicit depth-after-world authority` assertion. This is an inherited test/assertion state, not a regression from 8.1.82.

## Visual qualification limitation

No fresh live-game framebuffer or physical-device visual sweep was available in this environment. Automated executable and static subsystem gates are not represented as a manual visual inspection.
