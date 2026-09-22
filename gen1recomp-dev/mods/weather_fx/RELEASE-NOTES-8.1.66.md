# Weather FX 8.1.66 — Surface-Conformal Voxel Snow Repaint

Built directly from exact Weather FX 8.1.65 (`c5531191698a62ec50370f5da746b04cc832300db553faef154615a40dc473f1`).

## What changed

Snow accumulation is no longer presented as detached white caps on trees, ledges, roofs, or other raised voxel scenery.

- **Actual voxel-surface repaint:** Weather FX redraws the exact terrain mesh already rendered by the voxel host with a snow-only, depth-tested material pass. The host mesh, atlas, collision data, and source assets are never edited.
- **Exact tree/canopy landing:** On Voxel Nexus 2.0.17, SnowPack reads the same `Structures.roundStamps` quads that `ChunkMesher` submits to the terrain mesh. Falling physical snow therefore resolves against real horizontal hull faces, not a smooth invisible crown approximation.
- **Real gaps stay gaps:** If an X/Z point lies between visible tree/canopy hull faces, snow falls to the lower real support instead of stopping on an invisible tile volume.
- **No floating cap geometry:** Trees, roofs, ledges, and raised scenery use conformal repaint only. Physical mound geometry remains limited to ground, grass, and load-bearing ice where snow can genuinely gain visible thickness.
- **Cinematic replacement trees:** Voxel Nexus' cinematic vegetation is drawn after the stock terrain mesh. Weather FX registers a later companion pass and uses the host's readable depth buffer plus inverse camera transform to whiten the actual visible upper tree/canopy surface.
- **Local coverage:** Repaint is world-position based. One snow-covered tree/ledge can whiten while identical geometry elsewhere remains unchanged.
- **Progressive melt:** SnowPack remains the sole accumulation/melt authority. As depth decays, repaint coverage decays with it until the untouched original world is fully revealed.
- **Mixed-surface cells:** Snow patches carry their own support kind/profile/art. Tree and ground deposits inside the same 16x16 voxel cell cannot inherit each other's presentation classification.

## Preserved

8.1.65 persistent tornado roaming, 8.1.64 SnowPack physical depth/footprints, precipitation virtualization, connected water/ice, weather fronts, celestial systems, settings, audio, and native gameplay authority remain intact.

## Qualification boundary

The exact Voxel Nexus 2.0.17 source contract is executable/static-checked and the repaint GPU path is exercised with a deterministic graphics mock. A new physical GPU/LÖVE framebuffer capture is only claimed if recorded separately in the final qualification; no visual result is fabricated.
