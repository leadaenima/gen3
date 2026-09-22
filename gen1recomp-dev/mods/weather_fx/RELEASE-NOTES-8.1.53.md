# Weather FX 8.1.53 — Spatial Cloud-Sun Terrain Lighting

Built directly from exact Weather FX 8.1.52.

## What changed

- **A local sun hole no longer lights the whole map.** The cloud ray sampled at the player is now used only for visible celestial-disc/deep-sky/ray occlusion, not the shared world direct-light scalar.
- **World light uses regional cloud coverage.** Weather FX samples a bounded 3×3 world-space footprint around the rendered weather corridor and feeds that regional coverage into `CelestialEngine`.
- **Cloud-covered terrain stays spatially shaded.** `WorldCelestialLighting` projects the same rotated four-lobe macro cloud bodies used by CinematicAtmos occlusion onto real terrain. Areas under those projected bodies remain shaded; openings remain the bright areas.
- **No expensive new shadow system.** The pass is bounded to at most 18 visible cloud descriptors and four terrain lobes each (72 maximum patches) and reuses the existing single terrain-shadow draw. There is no per-pixel cloud march, framebuffer shadow texture, or new large resident buffer.

## Preserved

8.1.53 preserves 8.1.52 independent non-homing storm fronts, frame-smooth front clouds, downward remote rain, physical front-distance audio, the indoor 40% retained weather-audio floor, persistent CYCLE/front state across maps, exclusive front-vs-CYCLE authority and named-weather front disabling. It also preserves 8.1.51's zero-upload distant-front instancing, exact 9,000-particle MAX budget, 62% remote/local handoff and all 68 player settings.
