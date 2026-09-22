# Weather FX 8.1.97 Final Audit

## Scope

Built directly from exact Weather FX 8.1.96 (`weather_fx-core-8.1.96.zip`, SHA-256 `7540ff129ab62dcdf325b1c6d8fe9f431aff8465b48f22c7dab1ef3485b35f83`). 8.1.97 is a player-settings audit/reliability release.

## Complete settings audit

The player-facing schema now contains **79 distinct controls**. Every control was exercised through the real Settings reader/choice tables and audited for registration, persistence/live mirror behavior, valid defaults/choices, submenu placement, help text, runtime consumption, and simultaneous maximum-load compatibility.

Focused executable totals:

- complete player-settings interaction audit: **2298/2298 PASS**
- settings runtime choices/behavior: **757/757 PASS**
- advanced settings pipeline: **42/42 PASS**
- settings menu: **35/35 PASS**
- complete settings descriptions: **1930/1930 PASS**
- live settings change chain: **17/17 PASS**
- 8.1.82 settings additions regression: **50/50 PASS**
- simultaneous maximum-settings profile: **10/10 PASS**
- settings/runtime static+executable audit: **278/278 PASS**
- 8.1.97 duplicate/RAVE-control regression: **16/16 PASS**
- RAVE soundtrack ownership regression: **24/24 PASS**
- exact uniqueness audit: **79 keys / 79 labels / 0 placement issues**

## Duplicate-setting cleanup

The audit found one real player-facing duplicate: **WEATHER VISUALS** duplicated the OFF behavior already provided by **BATTLE WEATHER**. The duplicate row is removed. **BATTLE WEATHER** is now the single `OFF / SUBTLE / FULL` visual authority, while **WEATHER RULES** remains an independent gameplay-mechanics setting.

`3D WEATHER DISTANCE` and `EFFECT DISTANCE` were not duplicates, but their names were easy to confuse. The former is renamed **3D PRECIP DISTANCE** and its help now explicitly states that it controls falling precipitation reach relative to the live voxel render distance, while EFFECT DISTANCE is the broader expensive-detail/performance radius.

No other duplicate keys, duplicate player-facing labels, or repeated submenu placements remain.

## New player controls justified by the audit

Two controls were added because the newer RAVE system had no dedicated accessibility/audio controls:

- **RAVE STROBE — OFF / REDUCED / FULL**. FULL preserves the authored per-song hard strobe. REDUCED prevents full-rig blackout while retaining softer outer choreography. OFF removes hard blackout gating while retaining moving lasers, illuminated fog, color, and beat-reactive motion. The executable Laser Floor 160-BPM check produced `54 -> 0` fixtures in FULL, retained 9 fixtures at the same blackout phase in REDUCED, and retained 49 in OFF.
- **RAVE MUSIC — OFF / 50% / 75% / 100% / 125%**. It is subordinate to WEATHER VOLUME rather than a second master. OFF stops the stream/decoder and releases native game-music ownership immediately.

No additional player settings were added: the remaining apparent overlaps are intentional master/sub-control relationships (QUALITY vs individual performance controls, WEATHER VOLUME vs thunder/wind/RAVE sub-controls, WEATHER STRENGTH vs family-specific precipitation amounts, LIGHTNING vs flash/frequency, and TORNADO vs frequency/duration/pickup).

## Whole-mod regression

The maintained developer sweep passes **112/112 programs**, including 2D/3D precipitation, full-render-distance snow, fronts, clouds, Battle Art and Voxel Nexus water ownership, NPC lightning, tornadoes, celestial systems, audio, battles, seasons, RAVE show/audio, pause-menu weather, settings, performance, compatibility, and `test_mod.py --lua`.

`test_mod.py --lua` independently reports **193 passed, 0 failed, 0 skipped**.

## Runtime delta versus exact 8.1.96

Runtime Lua changes are limited to:

- `lib/Settings.lua`
- `lib/Audio.lua`
- `lib/RaveMusic.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`

Test/tool/documentation changes update current expectations, exercise all settings, and advance release identity. No weather-family simulation ownership was moved.

## Truth boundary

The audit is an exhaustive executable settings/runtime regression, not a claim that every one of the 79 settings was individually photographed in a real-game framebuffer. Previously qualified live framebuffer paths (pause-menu weather, RAVE illuminated fog/strobe, NPC lightning) remain inherited and their runtime regressions remain passing.
