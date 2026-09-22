# Weather FX 8.1.55 — Final Release Audit

## Release identity

Weather FX **8.1.55**, “Smooth World-Anchored Snow Motion”, is built directly from exact Weather FX 8.1.54 (`f820ceec852748c4900a0ec3631ccd28f198b7ceb425e43f78ca132dbf2dbf79`).

The production runtime delta is deliberately surgical: only `lib/ProceduralSnowField.lua` changes from 8.1.54. `lib/voxel_atmos/WorldPrecip.lua`, `lib/ProceduralPrecipField.lua`, `lib/Quality.lua`, storm fronts, weather authority, audio, cloud/sun lighting, water and celestial runtime remain byte-identical to the preserved 8.1.54 baseline where covered by the runtime freeze.

## Snow-motion repair

8.1.54 made the procedural GPU snow field the entire visible snow/blizzard population after real driver proof. That exposed two weaknesses that were much harder to notice when the field was only distant background snow:

1. visible fall/tumble consumed the caller simulation clock directly, so repeated/stepped timing could read as close-range stutter;
2. the old 64-unit streaming anchor interpolated toward the player's next cell, physically dragging every procedural flake with the player and visibly recentering the blizzard when a boundary was crossed.

8.1.55 gives procedural snow a dedicated monotonic presentation clock. Host presentation time advances the visual fall/tumble phase independently of repeated caller simulation timestamps; long pause/debugger gaps are clamped so resume cannot jump the whole field. On hosts without a presentation timer, the caller clock remains the fail-open source but cannot reverse the snow phase.

Snow streaming now uses immutable **256-unit world anchors**. No current anchor is interpolated through world space. When the player needs another streamed snow region, the existing visual population is progressively repartitioned between the old fixed anchor and the new fixed anchor. There is never an intermediate player-following anchor.

## Density and performance preservation

This release does **not** change snow density or authored population ceilings. `WorldPrecip` and `Quality` are byte-identical to 8.1.54, preserving MAX snow 100,000 and MAX blizzard 200,000 plus the <=96 Lua snow interaction-probe contract after GPU proof.

During anchor handoff, the requested snow instance count is partitioned between two fixed fields rather than duplicated. The executable regression proves the total submitted instance count remains exactly the requested count. The split may introduce at most one additional instanced chunk/draw boundary while a handoff is active; there is no second complete snow population, no new framebuffer, no new texture, no new per-particle Lua state and no resident world grid.

Snow ground collision, settling, banks and footprints remain intentionally disabled from 8.1.54 pending a separate corrected collision implementation.

## Qualification

Current release gates:

- 8.1.55 runtime delta: PASS; only `lib/ProceduralSnowField.lua` changed.
- 8.1.55 runtime freeze: **162/162 PASS**.
- 8.1.55 package surface: **14/14 PASS**.
- 8.1.55 performance preservation: **7/7 PASS**.
- 8.1.55 snow-motion executable regression: **10/10 PASS**.
- 8.1.54 near precipitation virtualization: **17/17 PASS**.
- 8.1.54 MAX precipitation virtualization: **8/8 PASS**.
- strict 3D pipeline integrity: **117/117 PASS**.
- all shipped Lua source/test units parse: **275/275 PASS**.
- all shipped Python units parse: **187/187 PASS**.

The entire maintained `tools/run_all.py --lua` command list was executed in four contiguous bounded segments because the monolithic inherited stress wall exceeds one execution window. Every segment completed with explicit process exit code **0** and final marker `all ok — safe baseline for next revision`.

## Verdict

**PASS.** Weather FX 8.1.55 supersedes 8.1.54 as the release candidate baseline for smooth, world-anchored procedural snow while retaining 8.1.54 particle density, GPU virtualization and snow-ground collision suspension.
