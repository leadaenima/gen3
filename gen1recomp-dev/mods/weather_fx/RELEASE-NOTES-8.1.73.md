# Weather FX 8.1.73 — World-Anchored Precipitation / Map-Entry Reprime

## Fixes in this release

### 3D rain no longer moves with the player
The procedural rain/hail renderer now keeps a fixed world-cell anchor. Walking inside that world region does not translate the precipitation field with the player. Crossing to a new anchor region uses a smooth old/new world-anchor handoff rather than camera/player parenting. The anchor grid automatically becomes smaller at reduced 3D WEATHER DISTANCE values so the player remains inside the precipitation field even at short ranges. Rain streak proportions and ballistic drift were also brought back toward the proven CPU rain presentation.

### Snow accumulation follows the weather render distance
The SnowPack aggregate sampler no longer uses the historical local ~108-unit radius. It samples the entire effective snow field radius produced by **3D WEATHER DISTANCE**. At 100% with WEATHER FRONTS OFF, that is the voxel render distance; at 75/50/25%, accumulation coverage follows the same reduced Weather FX-only distance. The bounded sample rate is preserved for performance, so the larger field is spread out rather than increasing CPU work in proportion to area.

### Snow/blizzard fountain and tight overhead-circle ownership
Weather FX now preflights the real procedural snow backend before `WorldPrecip.update` allocates the visible population. A valid procedural backend can own the distributed field on the first visible snow/blizzard frame instead of exposing a huge legacy overhead instance pool first. Hosts that fail the procedural instance validation continue to fail open to explicit CPU particle cards. WEATHER FRONTS OFF also hard-gates stale distant-front precipitation so it cannot transiently duplicate local snow/blizzard.

### Weather reappears immediately after map changes
Map entry now uses the live gameplay player's new map position to re-prime and reanchor precipitation in the same update. Rain, snow/blizzard, and hail no longer depend on taking a step before their streams become visible again.

## Preserved behavior

- `3D WEATHER DISTANCE` 25/50/75/100% remains unchanged.
- The percentage distance override remains active only when WEATHER FRONTS is OFF.
- `SNOW ACCUMULATION` ON/OFF remains unchanged.
- Approved snow-bank heights remain unchanged.
- Existing procedural seed-collapse detection remains active.

## Qualification note

The reported behaviors are covered by executable regressions and inherited package gates. A fresh live-game framebuffer capture on the user's graphics host was not produced during this build, so final visual confirmation on that host remains the last empirical check for the exact fountain/tube appearance.
