# Weather FX 8.1.28 — World-Scale Realism Phase 1

Weather FX 8.1.28 is built from the real-host-qualified 8.1.27 baseline. This release deliberately does **not** add more weather names. It makes existing weather inhabit the flat voxel world more physically.

## Flat-world design rule

There are no mountains in this world, so 8.1.28 removes the leftover mountain/peak microclimate modifier and does not use orographic weather. Local variation is driven by horizontal voxel context: towns/buildings, forest canopy, water/shorelines, open routes, shelter, wind shadows and small flat drainage irregularities.

## World-scale realism implemented

1. **Horizontal microclimates** — a bounded 5x5 live voxel footprint derives built/canopy/water/open fractions. Town footprints retain a small amount of heat; forests cool and humidify; water increases humidity/fog affinity; open routes stay more wind exposed.
2. **Building/forest shelter** — shelter is directional to the live wind. Solid roofs/buildings strongly block precipitation and wind; tree canopy is explicitly permeable and only partially shelters the player/world.
3. **Real rain interception** — near-surface 3D rain now queries exact voxel/model support. Roofs and raised props stop drops; canopy catches most drops but allows a deterministic fraction through. Far/high precipitation stays free of collision work.
4. **Persistent wet ground** — 3D puddle appearance now follows the persistent surface wetness state after rain stops instead of disappearing immediately with the rain channel. Water/solid shelter reject inappropriate land-wet deposition.
5. **SnowPack redesign** — persistent 3D accumulation is restored through the dedicated radial-bank path, not the historical shared puddle shader. Snow never accumulates on water, retains less on canopy/roofs/thin props, footprints only form on walkable ground/grass, and cleanup/melt responds to rain, heat and local temperature. All state/draw pools remain bounded.
6. **Visible distant weather** — existing finite StormCells publish a maximum of four useful far-field descriptors. Rain/hail/snow and genuine low fog create depth-tested horizon curtains before local precipitation reaches the player. Buildings/forests can occlude them naturally. Dry sand/ash cells are intentionally excluded so they cannot look like blue rain shafts.
7. **Local weather acoustics** — building shelter suppresses direct rain/wind, forest canopy softens high-frequency rain, dense town shelter partially muffles thunder, and nearby stormy water publishes stronger water-ambience authority.
8. **True shared lightning illumination** — the real Lightning flash envelope now enters DynamicLighting, UnifiedLighting and LightProbeGrid, allowing nearby voxel/material lighting consumers to brighten with a bolt rather than depending only on the existing screen/cloud/world-bolt presentation.
9. **Flat drainage** — Hydrology no longer models fake height/slope. Bounded deterministic basin/outlet differences represent curb/soil/drain behavior on a flat map while voxel shelter controls rainfall collection.

## Performance contract

This phase reuses existing spatial systems instead of adding a large new simulation grid. Distant weather is capped at four StormCells and twelve curtain quads, structure collision is only queried near the inhabited rain layer, the existing SnowPack pools remain bounded, and the local voxel footprint is a cached 5x5 sample. No particle count or visual-quality target is reduced.

## Preserved 8.1.27 repairs

The projection-safe sealed-cloud logic, live mesh growth, dead puddle-uniform cleanup and LÖVE 11.5 NightSky texcoord fix from 8.1.27 are retained unchanged except where CinematicAtmos intentionally gains the new distant-weather/persistent-wetness work.


## Live Gen1Recomp qualification repairs

The final live Gen1Recomp 0.2.53 / LÖVE 11.5 pass exposed and fixed two compatibility issues before packaging:

- The private voxel namespace now resolves Weather FX-owned realism/environment helpers from Weather FX before probing the host, avoiding false host "missing module / reinstall" warnings for modules such as WeatherState, DistantWeather, precipitation fields and CloudField. True voxel/render seams remain host-owned.
- NPC lightning now accepts the current Voxel Realism `Voxel3D.size()` / `Voxel3D.canvas()` function contract as well as the older canvas-field shape. This removes a protected storm-pass error where a function was indexed as a Canvas.

## Qualification boundary

Automated tests verify executable shelter/microclimate/distant-weather/snow/lightning contracts and inherited runtime behavior. Real Gen1Recomp/LÖVE runs are used for host loading/shader/runtime validation, but subjective final appearance still requires player-visible inspection on the target camera/GPU.
