# Weather FX 8.1.44 — Public Battle Art Exclusive Water Ownership

## Why this release exists

Weather FX 8.1.43 correctly removed the legacy Voxel Nexus outer underlay when Weather FX owned `VOID FILL = WATER`, but the current public **Battle Art Voxel Fork 1.10.1** has a subtly different water-export contract despite using the same legacy mod id, `BATTLE_ART_VOXEL_FORK`.

Public Battle Art 1.10.1 exposes the same structured wave tables and `_waveTime` clock used by its reflective water shader, but it does **not** expose the `_trainSource` helper added by the Voxel Nexus lineage. Weather FX had been using `_trainSource` as part of its structured-water capability test. As a result, public Battle Art was incorrectly sent down the legacy fragment-relief compatibility path. Weather FX replaced the host draw list, but Battle Art's own 0..5-world-pixel relief engine remained active over that replacement instead of yielding geometric relief to the Weather FX physical mesh.

## 8.1.44 repair

- The shared bridge now fingerprints the actual public Battle Art 1.10.x `Water` capability shape instead of assuming every `BATTLE_ART_VOXEL_FORK` installation is Voxel Nexus.
- Public Battle Art is recognized only when the host exposes its structured `WAVE_TRAINS`, `WAVE_SWELL`, `WAVE_BEND`, `_waveTime`, and `begin/draw/finish` reflective pass while **not** exposing Voxel Nexus' `_trainSource` helper.
- That fingerprint is published into `ConnectedWater` as renderer metadata only; no host gameplay state is modified.
- `ConnectedWater3D` now permits true tessellated physical-water ownership for that exact public-host capability.
- After the Weather FX physical mesh is prepared successfully, the host `Water.WAVE_HEIGHT` is set to `0` for the owned frame. Battle Art still supplies its reflection, depth-test, sky/sun/moon reflection and cast-reflection pass, but its second geometric relief surface is gone.
- The existing 8.1.40 `WorldUnderlay` preflight/suppression remains active, so the public host's giant underlay cannot remain as another VOID surface underneath the Weather FX ocean.
- The native Battle Art water draw list is still not submitted when Weather FX owns the replacement. `WATER STYLE = ORIGINAL` and any failed Weather FX preparation remain fail-open to the untouched host renderer.

## Exact public-host source checked

The repair was qualified against the public `absol89/DramaticShapeVoxelMod` **1.10.1** source contract. Relevant public modules are `manifest.json`, `lib/WorldUnderlay.lua`, `lib/VoxelScene.lua`, `lib/Water.lua`, and `lib/ChunkMesher.lua`. Public Battle Art's `WorldUnderlay` is a separate camera-following 32K-range floor, `VoxelScene.drawWater` is a late reflection/depth pass, and `Water.lua` contains a stepped heightfield wave engine (`WAVE_HEIGHT = 5`) that must not remain as a second geometric relief owner after Weather FX takes over.

## Dedicated regression

`tests/battle_art_public_water_8144_test.lua` proves:

- public Battle Art and Voxel Nexus are distinguished even though both use `BATTLE_ART_VOXEL_FORK`;
- public Battle Art without `_trainSource` enters true Weather FX physical mesh ownership;
- native Battle Art geometric relief is zeroed only after successful Weather FX ownership;
- one finite Weather FX VOID surface and one holed Weather FX outer ocean are produced;
- Voxel Nexus remains on its existing `_trainSource` path;
- removing the new capability fingerprint deliberately reproduces the old fallback, proving the test catches the regression.

## Preserved behavior

8.1.43 exact constellation peak brightness, 8.1.42 researched aurora + winter snowstorms, 8.1.41 reachable world-scale storm fronts, 8.1.40 exclusive underlay ownership, living ponds/fish, physical waves, foam, tides, reflections, Surf bob, progressive ice and all gameplay-safety contracts remain unchanged.
