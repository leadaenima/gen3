# Weather FX 8.1.84 Final Audit

## Baseline
Exact Weather FX 8.1.83.

## Defect
Weather FX exposed two player weather selectors:
1. the engine OPTIONS `WEATHER` pipeline row;
2. Weather FX Mod Manager `WEATHER MODE`.

They were not truly one state. The engine ladder mirror updated `_runtimeAlways` but not the runtime option cache read by the Mod Manager, and WeatherState evaluated the stale hard-OFF option before accepting a newer OPTIONS ladder rung. This could make the OPTIONS selector appear not to change weather and could reassert OFF/named state from the other menu.

## Repair
- Both selectors now mirror one canonical `always` weather value immediately.
- OPTIONS changes update Weather FX runtime cache, Mod Manager persisted option, save mirror and loader mirrors.
- Mod Manager changes continue to push the live engine pipeline rung immediately.
- WeatherState reconciles the current engine OPTIONS rung before testing hard OFF.
- The actual OPTIONS weather row is decorated so stepping it publishes the change immediately instead of waiting for a later climate tick.
- OFF -> AUTO and OFF -> named weather work from either surface.
- Named weather from either surface still disables WEATHER FRONTS so fronts cannot silently steal authority.
- No option-store writes occur on unchanged per-frame synchronization.

## Runtime delta
Exactly three runtime Lua files differ from exact 8.1.83:
- `lib/Settings.lua`
- `lib/WeatherState.lua`
- `main.lua`

## Regression proof
- dual selector: **15/15 PASS**;
- negative control exact 8.1.83: **6 PASS / 9 FAIL**;
- inherited/full developer sweep after repair: **84/84 programs PASS**.

No precipitation counts, rendered distances, 8.1.83 snow smoothing, 2D/3D battle ownership, rendered-world hail/sand/ash correction, sun-glare camera fix, water physics, tornado geometry, wind engine, audio assets, weather catalogue, or quality ceilings were intentionally changed.
