# Weather FX 8.1.49 — Professional Player Settings Audit

## What changed

Weather FX no longer exposes its settings as a developer-oriented flat list. The complete 68-setting surface is organized into 11 shallow categories:

1. **WEATHER** — active weather, overall strength, duration, renderer, indoor lighting.
2. **PRECIPITATION** — rain, snow, fog, sand, dust, splashes and snowflake style.
3. **WORLD & CLOUDS** — clouds, water, wind, wet ground, rainbows and leaf colour.
4. **WEATHER BEHAVIOR** — transition speed, regional fronts and local weather variation.
5. **STORMS & TORNADO** — lightning, flash brightness, storm darkness, character strikes and tornado controls.
6. **SKY & SEASONS** — time, seasons, celestial events, sky smoothing and sun/moon motion.
7. **SOUND** — main weather volume, indoor weather, thunder and wind audio.
8. **WILD POKEMON** — weather-influenced encounters, legendary events and follower weather damage.
9. **BATTLES** — weather amount, visuals, rules, amplified rules and battle backgrounds.
10. **PERFORMANCE** — master quality, automatic adjustment, frame-rate target and advanced workload/detail limits.
11. **TESTING** — diagnostics and precipitation debug tools.

Navigation is only **Weather FX → category → setting**. There are no categories inside categories.

## Plain-language labels and descriptions

- `WX` shorthand is removed from player-facing settings.
- `SFX`, `DMG` and similar developer abbreviations are not used as setting labels.
- The internal stored value `config` remains supported for backward compatibility but is displayed to players as **DEFAULT**.
- **WX ENCOUNTERS** is replaced by a plain-language weather/wild encounter setting.
- **LEGENDARY EVENTS** now explains the actual implementation: Articuno/Zapdos/Moltres in Gen 1 and Raikou/Entei/Suicune/Lugia/Ho-Oh/Celebi when the active game supports Gen 2 species.
- Every setting has a complete player description. Descriptions are published as `help`, `description`, and `desc` so compatible stock/premium UI skins can show the same authoritative explanation.

## Compatibility

Existing setting keys and stored values are preserved. Players upgrading from 8.1.48 do not need to reset their Weather FX options. Custom `config.lua` defaults remain authoritative when a saved setting is in the internal `config` state; the menu simply presents that state as **DEFAULT**.

The only gameplay-runtime files intentionally changed from exact 8.1.48 are:

- `lib/Settings.lua`
- `lib/SettingsMenu.lua`

All weather engines, renderers, assets, audio systems, battle/encounter logic and performance implementations outside that settings surface are preserved.

## Qualification

The final audit covers:

- all **68/68** player settings;
- every selectable value through the menu persistence/live-update path;
- complete description coverage;
- real Gen1Recomp + Pokémon Yellow menu captures for every row;
- real gameplay framebuffer checks for representative precipitation, renderer, storm-darkness and diagnostic effects;
- inherited Weather FX rendering/gameplay/audio/voxel-host regressions.

See `PLAYER-SETTINGS-AUDIT-8.1.49.md` for the exact evidence and honesty boundary.
