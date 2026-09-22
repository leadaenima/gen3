# Weather FX 8.1.55 — Snow Motion Performance Preservation Audit

## Scope

8.1.55 fixes snow/blizzard visual stutter and player-following anchor motion without changing authored density or undoing 8.1.54 full-visual GPU virtualization.

## Preserved workload

- `lib/voxel_atmos/WorldPrecip.lua` is byte-identical to 8.1.54.
- `lib/ProceduralPrecipField.lua` is byte-identical to 8.1.54.
- `lib/Quality.lua` is byte-identical to 8.1.54.
- MAX snow/blizzard logical ceilings remain 100,000 / 200,000.
- After driver proof, snow CPU interaction state remains capped at <=96 probes by the unchanged WorldPrecip runtime.

## New snow streaming cost

The old renderer moved one procedural anchor through world space. The new renderer owns at most two immutable anchor coordinates during a handoff. The requested particle count is partitioned between those anchors, not duplicated, so total submitted instances remain exactly unchanged. Because the same instance population is split across two chunk streams, the handoff can require at most one additional `drawInstanced` chunk relative to an equivalent one-anchor count.

State added for the fix is only a few scalar anchor/clock values. No new Canvas, framebuffer, texture, mesh population, per-particle table, or resident world grid is added.
