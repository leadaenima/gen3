# Weather FX 8.1.39 — Universal Voxel Void-Water Ownership

## Why this release exists

8.1.38 fixed the visible outer water on the current Voxel Nexus stack, but its last-mile assumptions were too specific: Gen1 `OVERWORLD` map shape, Voxel Nexus's 32768-unit `WorldUnderlay`, and the presence of a normal host `VoxelScene.drawWater` call. That could leave native/flat VOID water visible on another voxel renderer even though Weather FX's physical ocean already existed.

8.1.39 makes the ownership rule belong to Weather FX rather than to one voxel mod.

## One VOID-water authority across voxel hosts

The shared `DramalessAtmos` bridge now publishes a capability record for every first-class voxel host it already supports:

- `BATTLE_ART_VOXEL_FORK` — Battle Art / current Voxel Nexus lineage
- `DRAMATIC_SHAPE`
- `DRAMALESS_SHAPE`
- `potato_voxel`, `POTATO_VOXEL`, `PotatoVoxel`
- `STADIUM2_OVERWORLD_MODELS` — Gen2/Stadium-style overworld host

The capability is deliberately tiny: host id, whether `VoxelScene.drawWater` exists, the shared VOID apron size, and an outer horizon range. A host's optional `WorldUnderlay.RANGE` is consumed when it exists; its absence is not an error and falls back to the bounded 32768-unit horizon already proven by 8.1.38.

## Gen1 + Gen2 outdoor detection

VOID WATER no longer requires `map.def.tileset == OVERWORLD`. `src.world.Map` is resolved at **call time** and `Map.isOutdoor(def)` is authoritative, which preserves the engine's generation-specific module swap. The fallback understands both Gen1 `tileset` and Gen2 `environment` vocabulary for older/test hosts.

This specifically closes the path where a Gold/Gen2 route could use a voxel renderer but never create Weather FX's VOID sea because it had no Gen1-style tileset field.

## Preferred reflective path

Dramatic Shape, Dramaless, Potato Voxel and the Battle-Art/Voxel-Nexus lineage expose a `VoxelScene.drawWater` seam. Weather FX wraps that one seam in memory and replaces the host's submitted synthetic water list with the existing connected-water meshes. The wrapper keeps `...` intact, so Potato's extra water-profile argument and future compatible extensions are not truncated.

The exact finite apron and the far physical sea therefore run through the host's real reflection/depth water pass rather than being painted as a screen overlay.

## No-drawWater fallback

A supported voxel host that lacks `drawWater` — or a frame where the host legitimately skips it — now gets a late depth-tested Weather FX compatibility pass. It contains **only** the synthetic finite VOID rows plus the presentation-only outer ocean. It never redraws authored pond/lake/river water and never gains gameplay ownership.

The fallback exists for compatibility, not as the primary quality path. Hosts with the standard water seam keep their exact reflective renderer.

## Preserved safety and 8.1.38 living ponds

- `WATER STYLE = ORIGINAL` immediately returns native host water.
- Failed Weather FX preparation stays fail-open to native host water.
- Synthetic/outer water still cannot become Surf cells, collision, ice support, SnowPack, hydrology, encounters, warps or progression.
- The 8.1.38 translucent authored ponds, shallow beds, 2–6 deterministic tiny fish per pond and 24-fish connected-world cap are unchanged.
- Existing waves, tides, reflections, foam, ice, rain ripples and Surf visual bob are unchanged.

## Qualification

`tests/void_water_all_voxels_8139_test.lua` exercises Gen2-shaped outdoor/indoor maps, all supported host ids, live capability range/ring changes, the normal VOID renderer separation and the no-`drawWater` fallback. `tools/test_8139_external_voxel_water.py` additionally checks a real extracted voxel-host tree for the water seam and optional underlay contract. Historical 8.1.38 pond/void and connected-water/player-safety suites remain mandatory.
