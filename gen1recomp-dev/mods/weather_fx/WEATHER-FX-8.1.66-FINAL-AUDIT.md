# Weather FX 8.1.66 — Final Audit

## Baseline / runtime scope

Built from exact 8.1.65. Intended behavioral runtime delta:

- `lib/SnowPack.lua`
- `lib/DramalessAtmos.lua`
- `lib/voxel_atmos/WorldPrecip.lua`
- new `lib/SnowSurfacePaint.lua`

All other inherited runtime files must remain byte-identical to the 8.1.65 runtime baseline.

## Repaint architecture

SnowPack remains physical deposition and melt authority. `SnowSurfacePaint` consumes the bounded current SnowPack draw population and builds a low-resolution world-space coverage/height field. Stock voxel terrain is repainted by redrawing the exact cached host terrain mesh with depth testing and no depth writes. Raised/tree/roof snow does not generate the old independent bank geometry. Ground/grass/ice retain physical snow thickness.

Voxel Nexus 2.0.17 tree/canopy landing uses its exact `Structures.roundStamps` horizontal quads. The same stamps are expanded into the terrain mesh by `ChunkMesher`, so SnowPack landing and repaint presentation share the real host geometry. Real gaps fall through.

Voxel Nexus cinematic replacement vegetation bypasses the stock terrain draw. Weather FX therefore uses a late `opaque_after_terrain` companion provider, after Voxel Nexus' priority-50 vegetation provider, and reconstructs the visible world point from the host's readable depth texture. Only irregular tree/canopy SnowPack coverage is admitted on this late path.

## Safety / ownership

- No host file, atlas, map, collision table, or mesh data is mutated.
- Repaint installation is in-memory and restorable.
- Unsupported/headless paths fail open to the original host draw.
- Snow melt removes repaint rather than trying to reconstruct original materials.
- Water remains rejected except load-bearing ice.
- Native gameplay/collision authority is unchanged.

## Evidence boundary

Headless executable tests and exact-host source contracts qualify the changed logic. Physical-device/GPU framebuffer claims are recorded only when actually available; absence of such a capture is not counted as a pass.
