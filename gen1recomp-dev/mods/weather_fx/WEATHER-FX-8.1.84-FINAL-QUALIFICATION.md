# Weather FX 8.1.84 Final Qualification

Built directly from exact Weather FX 8.1.83.

## Player-visible repair
The base-game OPTIONS `WEATHER` row and Weather FX Mod Manager `WEATHER MODE` row now share one live and persisted authority. Either selector changes the active weather, mirrors the other selector, and can recover from OFF.

## Source qualification
- 8.1.84 dual-selector regression: **15/15 PASS**.
- Negative control on exact 8.1.83: **6 PASS / 9 FAIL** as required.
- Full 8.1.84 developer sweep: **84/84 programs PASS**.
- Settings runtime remains **731/731 PASS** within the sweep.
- Complete player-setting interaction suite remains green within the sweep.
- 3D pipeline, feature audit, performance invariants, host compatibility, 2D/3D weather families, snow motion, rendered-world hail/sand/ash, battles, sun glare/celestials, water/wind, tornado/lightning, audio, seasons and gameplay suites remain green within the sweep.

## Runtime scope
Only three runtime Lua files differ from exact 8.1.83:
- `lib/Settings.lua`
- `lib/WeatherState.lua`
- `main.lua`

Exact-package integrity and replay are recorded in the release-side exact-package logs generated after the archive is frozen.
