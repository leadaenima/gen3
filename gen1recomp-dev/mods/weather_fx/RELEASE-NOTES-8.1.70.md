# Weather FX 8.1.70 — Fronts-Off World Snow/Hail / Procedural Seed Validation

## What is fixed

- **WEATHER FRONTS OFF is whole-world again.** Snow, rain and hail now expand to the rendered-world far radius instead of behaving like a small local weather bubble around the player.
- **Hail no longer degenerates into a player-local shower column in CPU fallback.** The hail family now inherits the same world-scale radius contract used by the fronts-off fallback field.
- **Broken instanced snow/hail hosts fail open correctly.** Procedural snow and precipitation renderers now run a one-time offscreen per-instance seed validation. If the host driver collapses all instances into one seed (the visible symptom is a vertical sky plume or shower tube), Weather FX disables the procedural far-field path and keeps the proven CPU renderer authoritative.
- **Wind routing is corrected.** Procedural snow uses the snow wind channel; procedural hail/sand/ash use the grain wind channel.

## Preserved behavior

- The player-facing **SNOW ACCUMULATION** ON/OFF setting added in 8.1.69 remains intact.
- Approved 8.1.68 snow-bank heights/shapes and the 45-second startup ramp are unchanged.
- Existing distant-front snow handoff, max-population precipitation virtualization, and point-plume protections remain inherited.

## Regression coverage run

- `tests/fronts_off_world_precip_8170_test.lua`
- `tests/procedural_instancing_validation_8170_test.lua`
- `tests/snow_accumulation_setting_8169_test.lua`
- `tests/procedural_far_snow_test.lua`
- `tests/snow_point_plume_8159_test.lua`
- `tests/max_precip_virtualization_8154_test.lua`
