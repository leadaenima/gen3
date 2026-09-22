# Weather FX 8.1.40 — Exclusive Void-Water Handoff

## Why this release exists

8.1.39 correctly replaced the host water list at `VoxelScene.drawWater`, but current Voxel Nexus also draws a separate giant `WorldUnderlay` before terrain. That outer plane is not part of the water draw list, so it could remain visible beneath Weather FX's physical VOID ocean and look like two water surfaces fighting.

## Exclusive VOID-water ownership

When all of the following are true:

- `WATER STYLE = WEATHER FX`;
- the live engine reports outdoor `VOID FILL = WATER`;
- Weather FX has observed and built its presentation-only outer sea; and
- the physical Weather FX water renderer successfully preflights for the current voxel frame;

Weather FX suppresses the host's **outer `WorldUnderlay.draw()` plane only**. The physical Weather FX finite apron and far ocean are then the sole visible VOID-water surface.

The preflight result is reused by the later `VoxelScene.drawWater` wrapper in that same frame, avoiding a second water-mesh preparation pass.

## What is deliberately not suppressed

`WorldUnderlay.drawFootprints()` remains untouched; these loaded-map safety footprints remain active beneath authored terrain. Those low per-map safety floors prevent a literal hole inside loaded authored terrain from exposing the outer ocean. Authored lakes, rivers and ponds continue through Weather FX's existing water ownership path; the 8.1.38 translucent ponds, shallow beds and tiny fish remain unchanged.

## Fail-open behavior

If `WATER STYLE = ORIGINAL`, the VOID mode is not WATER, the map is not eligible, or the Weather FX preflight fails, the host underlay and native water path are left untouched. No host files are edited on disk.

## Preserved systems

8.1.40 preserves 8.1.39 universal voxel-host capability routing, Gen1/Gen2 outdoor detection, the no-`drawWater` synthetic-VOID fallback, physical waves, reflections, tides, foam, rain ripples, Surf visual bob, freezing/ice, SnowPack and gameplay/collision safety.
