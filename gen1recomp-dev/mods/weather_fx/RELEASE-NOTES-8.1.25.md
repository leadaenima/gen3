# Weather FX 8.1.25 — Constellation Uniformity

Weather FX 8.1.25 is built from 8.1.24 and preserves its zero-quality-loss performance architecture, weather-front behavior, cloud-height controls, shadow engine, particle counts, cloud counts, star catalogue, constellation catalogue, and all player-facing weather timing.

This release fixes three sky-presentation issues:

1. **Uniform constellation brightness** — all 25 approved traced constellations retain the same per-star primary/secondary hierarchy, but the full-shape perceived brightness is normalized so very dense traces no longer overpower sparse traces and sparse traces are no longer lost beside dense ones.
2. **Better constellation spacing** — anchor placements are gently repelled so the few constellations that ended up too close together are spread farther apart without changing the traced drawings themselves.
3. **Same building-light response as stars** — constellations now dim near buildings using the same BuildingLight star-scale response as ordinary stars instead of a compressed, brighter-only variant.

Preserved-output contract:
- no reductions to particles, clouds, stars, constellations, planets, draw distance, quality tiers, or storm coverage;
- no changes to StormCell counts, WeatherFronts behavior, cloud-height options, or WeatherShadowMap quality;
- no changes to approved constellation subjects, trace density, or point count.
