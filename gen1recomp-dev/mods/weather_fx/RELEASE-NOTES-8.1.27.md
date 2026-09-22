# Weather FX 8.1.27 — Live Host Repair

Weather FX 8.1.27 is built from 8.1.26 after a real in-game Gen1Recomp 0.2.53 / LÖVE 11.5 test using Pokemon Yellow and Voxel Realism 1.8.1. Unlike the earlier headless-only gates, this release incorporates defects observed in the actual running game and framebuffer.

## Fixed from live play

1. **Overhead cloud projection crash** — sealed overhead cloud cells can legitimately be admitted by world distance even when the cloud centre has no current NDC projection. The old code later performed arithmetic on nil `nx/ny`. 8.1.27 explicitly tracks projection validity and keeps the overhead-deck branch projection-safe.
2. **Dead puddle shader uniform** — the live LÖVE shader compiler optimized away `cloudCover`, while the runtime still attempted to send it, producing a protected-call warning/error. The unused uniform and send are removed; weather coverage authority elsewhere is unchanged.
3. **Atmosphere mesh overflow** — live weather transitions exposed LÖVE stream meshes that were created at the first frame's exact vertex count, then overflowed when a later weather frame needed more vertices. Cloud, rain, mist, roll-fog, particles, and god-ray fallback streams now use grow-only power-of-two capacities while uploading the exact current rows.
4. **NightSky shader validation failure** — LÖVE 11.5 exposes `VertexTexCoord` as a vec4 on this host; assigning it directly to the vec2 body UV varying caused the detailed celestial shader to fail validation. 8.1.27 uses `VertexTexCoord.xy`, allowing the real-host shader to compile.

## Live scenarios exercised

The real Yellow runtime was driven through Pallet Town with Weather FX loaded in both 3D and 2D presentation. Captured live scenarios included light rain, storm, snow, blizzard, fog, gale, psychic storm, hail, clear, 2D rain/storm/snow/fog/psychic storm, and clear-sky morning/day/evening/night camera states.

## Preserved output contract

- no reductions to rain/snow/hail particle populations;
- no cloud-count or cloud-field reductions;
- no star/constellation/planet population reductions;
- no draw-distance or quality-tier reductions;
- no changes to Weather Duration timing semantics;
- no changes to StormCell/front/cloud-height controls;
- no WeatherShadowMap quality reductions.

Separate Voxel Realism 1.8.1 live-host warnings found during the run (bundled Stadium importer path, `src.render.GBCFX`, and missing optional compatibility modules) are not Weather FX code and are not modified by this release.
