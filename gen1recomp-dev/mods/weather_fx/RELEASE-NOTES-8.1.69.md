# Weather FX 8.1.69 — Snow Accumulation Toggle

Built directly from exact Weather FX 8.1.68.

## Player-facing change

A new **SNOW ACCUMULATION** setting is available in the in-game **PRECIPITATION** submenu directly below **SNOW AMOUNT**.

- **ON** (default): snow banks and footprints accumulate normally.
- **OFF**: existing Weather FX snow banks and footprints are cleared immediately and no new ground accumulation is created. Falling snow, snow weather, clouds, wind and other cold-weather effects continue normally.
- Turning the setting back **ON** starts accumulation again from a clean field and preserves the normal 8.1.68 startup ramp.

## Preserved behavior

The setting does not change the approved snow-bank height profile. Ground remains 3.60 world units at full depth, grass 3.20, raised surfaces 2.40, trees 1.85 and thin props 0.90. The 8.1.68 distributed golden-angle deposition field and coalesced broad-bank behavior are unchanged.

## Runtime delta vs 8.1.68

Exactly three runtime files change:

- `lib/Settings.lua`
- `lib/SnowPack.lua`
- `lib/voxel_atmos/WorldPrecip.lua`
