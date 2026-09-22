# Weather FX 8.1.72 — 3D Weather Render Distance

## New in-game option

**PRECIPITATION → 3D WEATHER DISTANCE**

Choices: **25% / 50% / 75% / 100%**. Default is **100%**.

- With **WEATHER FRONTS OFF**, 100% means rain, snow, hail, and the WorldPrecip airborne weather field use the live voxel render distance.
- 75%, 50%, and 25% reduce only the Weather FX field to that percentage of the voxel distance.
- The option never changes the voxel/world render distance itself and cannot increase weather beyond it.
- With **WEATHER FRONTS ON**, the inherited regional/front-owned reach remains authoritative.
- Grain populations are area-scaled when the fronts-OFF field is shortened, so reducing distance does not turn hail into an artificially dense shower.

## Preserved fixes

- 8.1.71 exact live voxel-distance matching at the default 100%.
- 8.1.70 procedural instancing validation/fail-open protection against the snow fountain and hail tube.
- 8.1.69 SNOW ACCUMULATION ON/OFF.
- 8.1.68 distributed/coalesced snow-bank behavior and approved snow-bank heights.
