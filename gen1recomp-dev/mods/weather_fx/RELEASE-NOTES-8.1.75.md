# Weather FX 8.1.75 — Rain Walk Continuity / Low-Population World Ownership

## What was still wrong in 8.1.74

8.1.74 correctly removed fronts-OFF mesoscale dry-band modulation, but the rain renderer still had a second split. When the logical rain population was above 1,200 drops, the validated procedural renderer owned the visible world-space field. Below 1,200 drops, Weather FX fell back to the legacy CPU visual pool. That CPU pool spawns and recycles around the live player position, so short 3D WEATHER DISTANCE values and/or lower particle budgets could still make rain follow the player and expose dry gaps as the player walked.

## 8.1.75 correction

- With **WEATHER FRONTS OFF**, once the procedural precipitation backend has passed its host validation, it owns visible rain at **every nonzero rain population**, not only above 1,200 drops.
- The CPU pool keeps at most **96 interaction probes** for lens/roof/wet-surface interactions; it is no longer the low-population visual authority in fronts-OFF mode.
- A same-weather **stable-rain continuity latch** preserves the last valid nonzero rain amount if one live channel snapshot briefly reports zero while walking. It does not override **RAIN AMOUNT OFF**, weather-id changes, or authored transition tapering.
- Procedural rain uses tighter fixed world-anchor cells at short/medium radii, so the field remains world locked but hands off before the player reaches a large uncovered sector of the configured weather-radius circle.
- WEATHER FRONTS ON keeps its prior low-population/backend behavior.

## Preserved

- 8.1.74 fronts-OFF uniform precipitation / no mesoscale dry bands.
- 8.1.73 map-entry reprime, fixed world anchors, SnowPack radius alignment, and snow/blizzard fountain preflight/fail-open protections.
- 8.1.72 3D WEATHER DISTANCE 25/50/75/100% semantics.
- 8.1.69 SNOW ACCUMULATION ON/OFF and approved snow-bank heights.

## New regression

`tests/rain_walk_continuity_8175_test.lua` directly exercises a 25% / 64-unit fronts-OFF rain field with a sub-1,200 logical population. 8.1.75 keeps it on the world-space procedural backend, preserves the exact weather radius, survives a simulated walking-time channel dropout, and still honors explicit rain OFF and authored transitions. The corrected build passes 12/12; exact 8.1.74 fails 7/12.
