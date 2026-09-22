# Weather FX 8.1.35 — Persistent Whitewater

8.1.35 fixes the white square patches that could appear to teleport across the 8.1.33/8.1.34 physical-water surface. The waves themselves were continuous; the problem was the foam generator. It re-tested fixed world sample points every frame and emitted a rectangular foam quad wherever a point crossed the crest/curvature threshold. As a crest moved between sample points, one quad could disappear while another distant quad appeared. Shore break also contained a time-bucket random re-roll.

## What changed

- **Persistent crest-following whitecaps.** Candidate identity is deterministic and stable. A whitecap follows the dominant wave's physical travel direction/speed rather than being re-selected from unrelated fixed points every frame.
- **No visible reset.** Each foam track has a smooth grow/hold/fade envelope. Analytic lifetime wrap occurs only while the geometry is collapsed to effectively zero size, so a reset cannot be seen as a jump.
- **Irregular ribbon geometry.** The main whitecap is now a tapered five-cross-section ribbon with slightly crooked edges instead of a four-corner rectangular patch. Both length and width shrink continuously with foam strength.
- **Attached curling lips.** Strong breakers still produce raised folded curl geometry, but the lip is generated from the same moving whitecap center and lifetime so it cannot detach and pop somewhere else.
- **Persistent river rapids.** River whitewater becomes tapered streaks that move downstream, fade to zero, and restart invisibly instead of reading as stationary white rectangles.
- **Stable shoreline breakers.** Coastline candidates are admitted from a static edge identity; the old time-bucket random reroll is removed. Breakers pulse smoothly and drift slightly along their own shoreline segment.

## Preserved behavior

8.1.34 Void Water Unification is unchanged: authored cartridge water and Voxel Realism `VOID FILL = WATER` share the same Professional Physical Water renderer and `WATER STYLE = WEATHER FX / ORIGINAL` ownership handoff. Void water remains visual-only and cannot affect Surf authority, collision, freezing/load-bearing ice, SnowPack, warps or progression.

Wave height, Gerstner-style orbital motion, tide datum, reflections, rain rings, progressive ice, Surf/player wave bob and shoreline pinning are preserved. No water/particle quality setting was reduced to hide the artifact.

## Regression contract

`tests/foam_persistence_8135_test.lua` proves that visible whitecap centers move continuously frame-to-frame, strength changes smoothly, whitecaps travel with the crest, lifetime resets occur at zero-size, tapered ribbon geometry is active, river rapid streaks are persistent, and the old time-bucket shoreline trigger is absent. All 8.1.34/8.1.33/8.1.32/8.1.31/8.1.30/8.1.29 water gates remain mandatory.
