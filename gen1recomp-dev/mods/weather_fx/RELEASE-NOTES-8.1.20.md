# Weather FX 8.1.20 — Weather Duration Testing Control

Weather FX 8.1.20 builds directly on the validated 8.1.19 shadow-engine release.

## New in-game setting

**WEATHER -> WEATHER DURATION** now exposes:

- NORMAL
- 2X
- 4X
- 10X
- 20X

The multiplier changes only weather dwell lifetime. 2X makes a weather expire in half its normal dwell time; 20X makes it expire in one twentieth. Edits take effect immediately on the current weather and existing regional fronts.

## Explicit non-effects

The setting does **not** change precipitation particle speed, snow/rain/ash fall velocity, wind simulation speed, cloud animation, audio playback, game speed, time-of-day/celestial speed, lightning cadence, or the duration of the natural weather-to-weather transition animation.

The former TEST-specific 3-second transition cap is removed so this control cannot accidentally speed transition presentation.
