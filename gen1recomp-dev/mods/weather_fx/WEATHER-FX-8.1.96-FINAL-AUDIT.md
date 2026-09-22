# Weather FX 8.1.96 Final Audit

## Scope

Built directly from exact Weather FX 8.1.95 (`weather_fx-core-8.1.95.zip`, SHA-256 `84a6616a662a3b0349db3169e961741f55c313f9918dfc1b4b71155f51a739a0`). 8.1.96 adds pause-menu weather visibility and an optional presentation freeze while retaining the completed 8.1.95 RAVE illuminated-fog/strobe work and all earlier fixes.

## Pause-menu weather behavior

The Scene presentation contract now recognizes the native Gen 1/Gen 2 START menus and their pause-menu descendants as transparent world overlays. Weather FX therefore continues drawing the world weather beneath those menus instead of treating them as unrelated opaque UI. Unknown non-pause UI remains fail-closed.

A new WEATHER option, `PAUSE MENU WEATHER`, exposes two values:

- `ANIMATED` (default): weather remains visible and continues animating while the pause menu is open.
- `FROZEN`: weather remains visible, but Weather FX presentation/evolution receives a zero animation delta until the pause stack closes. The held frame resumes from the same visual state instead of restarting or repopulating.

The freeze covers classic 2D precipitation/fog/wind phases and the 3D presentation paths, including procedural precipitation, voxel atmosphere/tornado presentation, and RAVE light-show motion. Host input/game UI remain live and Weather FX audio is not forcibly cut.

## Real framebuffer qualification

A fresh Gen1Recomp 0.2.53 / LÖVE 11.5 / Pokémon Yellow session was run with Battle Art Voxel Fork 1.10.4 installed. Battle Art's voxel pipeline was disabled to exercise the actual flat/2D weather presentation path.

Observed live behavior:

- HEAVY RAIN remains visibly rendered behind the native START menu.
- `ANIMATED` pause mode advances the Weather FX presentation clock and visibly changes precipitation.
- `FROZEN` pause mode reports zero presentation-clock delta and `animationPaused=true`.
- Two 1024x768 FROZEN framebuffer captures separated by 30 live frames are pixel-identical: **0 changed RGB pixels**.
- After START closes, `animationPaused=false` and precipitation resumes immediately from the held state.
- Independent framebuffer comparison: ANIMATED pair changed 114,532 pixels; FROZEN pair changed 0 pixels; resumed pair changed 133,821 pixels.

The screenshots are direct LÖVE framebuffer captures, not generated mockups.

## Regression

- Pause-menu focused regression: **23/23 PASS**.
- `test_mod.py --lua`: **193/193 PASS**.
- Settings descriptions: **1899/1899 PASS**.
- Current settings surface: **78 options registered**.
- Settings/runtime audit: **272/272 PASS**.
- 3D pipeline integrity: **117/117 PASS**.
- Feature integrity: **510/510 PASS**.
- Voxel-host contract: **27/27 PASS**.
- Revision gate: **80/80 PASS**.
- Maintained 8.1.96 developer sweep: **108/108 programs PASS** (104 completed in the bounded sweep process before the outer execution timeout, followed by the remaining four maintained gates individually; all returned success).

## Runtime delta versus exact 8.1.95

Runtime Lua changes are limited to:

- `main.lua`
- `lib/Draw.lua`
- `lib/EngineRuntime.lua`
- `lib/ProceduralSnowField.lua`
- `lib/Scene.lua`
- `lib/Settings.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`
- `lib/voxel_atmos/WorldPrecip.lua`

Test/tool/documentation changes update the setting count, exercise the pause-menu contract, and advance release identity only.

## Truth boundary

The live qualification uses software OpenGL in the preserved Gen1Recomp/LÖVE test environment. It is direct framebuffer proof of the requested pause-menu behavior, not a claim about FPS on every physical GPU/display.
