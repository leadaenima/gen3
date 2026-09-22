# Weather FX 8.1.70 Final Audit

Build basis: exact 8.1.69 package.

## Intent
Repair the user-reported fronts-off precipitation regressions:
1. snow/weather collapsing into a small circle around the player when WEATHER FRONTS is OFF;
2. a vertical snow plume / blast point in the sky;
3. hail presenting as a narrow shower tube.

## Runtime/code changes audited

- `lib/voxel_atmos/WorldPrecip.lua`
- `lib/ProceduralSnowField.lua`
- `lib/ProceduralPrecipField.lua`
- `tests/fronts_off_world_precip_8170_test.lua`
- `tests/procedural_instancing_validation_8170_test.lua`

## Findings

- WorldPrecip now resolves WEATHER FRONTS ON/OFF explicitly and promotes the snow/rain/hail fallback radii to whole-world coverage when fronts are OFF.
- Hail CPU fallback no longer stays on the older short local radius.
- Procedural snow and precipitation modules now self-test per-instance seed variation once before claiming the far-field path. A failed validation disables the procedural renderer and leaves the proven CPU fallback authoritative.
- Procedural wind channels are now correctly routed.

## Regression results

All executed tests passed:

- `snow_accumulation_setting_8169_test.lua` — 13 passed, 0 failed
- `procedural_far_snow_test.lua` — 14 passed, 0 failed
- `snow_point_plume_8159_test.lua` — 9 passed, 0 failed
- `max_precip_virtualization_8154_test.lua` — 8 passed, 0 failed
- `fronts_off_world_precip_8170_test.lua` — 9 passed, 0 failed
- `procedural_instancing_validation_8170_test.lua` — 6 passed, 0 failed

## Qualification

Result qualifies as Weather FX 8.1.70 pending in-game visual confirmation on the user's host/device, which is specifically what the new procedural-instancing fail-open logic is designed to protect.
