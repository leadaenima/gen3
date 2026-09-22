# Weather FX 8.1.34 — Void Water Unification

8.1.34 fixes the remaining flat-water path shown when Gen1Recomp's player option **VOID FILL = WATER** surrounds an OVERWORLD map with Voxel Realism's synthetic border-water apron. 8.1.33 correctly replaced cartridge-authored water, but a map with little or no authored water could still leave the voxel host's flat blue void-water draw untouched.

## What changed

- Weather FX now observes the live `src.render.TileRenderer.voidFill` authority used by Gen1Recomp 0.2.53.
- When the current map is `OVERWORLD` and VOID FILL is `water`, Weather FX reconstructs the exact Voxel Realism current-map apron: **3 border blocks = 96 px = 6 Weather FX cells** outside the authored map body.
- Connected neighbour map bodies use the same strict rectangle-overlap mask as Voxel Realism, so synthetic water cannot leak through connected routes/towns.
- The void apron is published as a **visual-only SEA body** to `ConnectedWater3D`, so it receives the 8.1.33 tessellated 3D surface, large crest/trough motion, Gerstner-style orbital motion, reflections, whitecaps, curling crest lips, shore foam and weather/wind sea-state response.
- The synthetic body never enters cartridge `bodyByCell`: it cannot change collision, Surf authority, ice walking, freezing, SnowPack support, humidity classification, warps or progression.
- VOID FILL WATER/TREES/BLACK is included in the hydrosphere topology key, so changing the player option updates the rendered apron without a map transition.

## WATER STYLE ownership

The existing in-game **ATMOSPHERE → WATER STYLE** setting now affects both authored water and void water through the same final render handoff:

- **WEATHER FX** — Weather FX owns the water pass, suppresses the flat voxel-host void-water draw, and submits the physical 3D void sea.
- **ORIGINAL** — Weather FX releases ownership immediately and forwards the voxel host's original water list unchanged, including its original VOID FILL water.

No Voxel Realism files are modified on disk. The integration is runtime-observed and fail-open: a host without the known engine/structured-water seams continues using its native presentation.

## Regression contract

The dedicated 8.1.34 test verifies void-only maps, exact apron width, neighbour masking, live WATER/TREES/BLACK changes, non-overworld exclusion, visual-only/no-ice semantics, physical 3D ownership, and WATER STYLE off/on handoff. All inherited 8.1.33/8.1.32/8.1.31/8.1.30/8.1.29 water gates remain mandatory.
