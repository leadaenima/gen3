# Weather FX 8.1.20 — Weather Duration Testing Control Audit

## Scope

8.1.20 is built directly from validated Weather FX 8.1.19. The intentional executable delta is restricted to:

- `lib/Settings.lua` — replaces the old SLOW/NORMAL/FAST/TEST weather-rotation row with `WEATHER DURATION = NORMAL / 2X / 4X / 10X / 20X`.
- `lib/WeatherState.lua` — applies the lifetime multiplier only to weather dwell timers and immediately rescales the current remaining dwell when the setting changes.
- `lib/Fronts.lua` — immediately rescales remaining regional-front dwell timers without accelerating front simulation `dt`.

Every other executable runtime/compat/asset file is byte-identical to the frozen 8.1.19 baseline, including the Weather FX-owned shadow engine.

## Lifetime-only contract

- NORMAL = 1.00x authored lifetime.
- 2X = 0.50x lifetime.
- 4X = 0.25x lifetime.
- 10X = 0.10x lifetime.
- 20X = 0.05x lifetime.
- Changing the setting during an active weather immediately rescales the remaining visible-weather and regional-front lifetime.
- The multiplier is not consumed by precipitation, cloud, wind, audio, celestial, lightning, game-time, or transition-animation modules.
- The former TEST-only `softDur <= 3s` visual-transition shortcut is removed. Natural weather-to-weather staging keeps its normal authored duration at every WEATHER DURATION setting.

## Executed validation

- 8.1.20 weather-duration contract: **21/21 PASS**.
- Settings runtime Lua: **500/500 PASS**.
- Player runtime regression: **36/36 PASS**.
- Synoptic transition behavior: **12/12 PASS**.
- Advanced settings pipeline: **37/37 PASS**.
- Settings menu: **32/32 PASS**.
- Maintained Lua suite: **181 passed / 0 failed / 0 skipped**.
- Settings descriptions: **1,339/1,339 PASS**.
- 3D pipeline integrity: **117/117 PASS**.
- Performance invariants: **66/66 PASS**.
- Voxel-host compatibility: **26/26 PASS**.
- Aggressive compatibility: **0 HIGH findings**.
- Strict full audit: **HIGH 0 / LOW 0**; only expected live-engine visual/hot-unload checks remain manual.

### Preserved 8.1.19 shadow engine

- Owned-shadow runtime: **26/26 PASS**.
- Shadow architecture contract: **12/12 PASS**.
- Projection monotonicity: **11/11 PASS**.
- Reproduced host projection reversals: **86**; Weather FX projection reversals: **0**.

### Preserved stress wall

- Manifest behavior freeze: **20/20**.
- Semantic snapshot: **791/791**.
- Config/quality snapshot: **304/304**.
- Weather catalogue: **1,407/1,407**.
- Celestial stress: **49,836/49,836**.
- Wind stress: **282,245/282,245**.
- BuildingLight stress: **411/411**.
- Night scheduler stress: **482,001/482,001** (104 shower nights / 1,000 frozen-seed nights).
- Weather-OFF cross-module contract: **15/15**.

## Validation boundary

Headless tests cannot replace the final subjective in-game check of menu presentation and transition appearance on an actual Gen1Recomp GPU/device. The runtime, settings wiring, timing isolation, compatibility and package contracts available in this environment are release-qualified.
