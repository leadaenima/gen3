# Weather FX 8.1.59 — Snow Point-Plume Repair

## Problem

During 3D snow or blizzard, the correct broad snowfall could be accompanied by a second dense vertical column that looked as though hundreds of flakes were spawning from one pixel.

## Root cause

The main player-local snow renderer was not collapsing. The artifact came from the separate distant StormCell hydrometeor slab. During the front-to-local transition, the distant slab could remain at substantial opacity while `WorldPrecip` was already drawing its complete local field. At close perspective the remote slab occupies a small angular width, so the duplicate snow reads as a vertical fountain.

Voxel hosts could also unnecessarily miss Weather FX's private `DistantFrontPrecip` module on the first lookup because that name was not included in the root-owned bridge list, forcing the CPU fallback and emitting a misleading host-module warning.

## Repair

- Added a snow/blizzard-only local-ownership handoff in `CinematicAtmos`.
- At negligible local snow (`<= 0.06`) distant snow is unchanged.
- As local snowfall becomes visible the duplicate slab fades smoothly.
- Once local snow is established the distant snow/blizzard slab is fully retired.
- Rain and fog bypass this handoff completely. Front clouds and lightning retain their existing ownership.
- The exact same handoff is applied to both GPU-instanced and CPU-fallback distant hydrometeor paths.
- Added `DistantFrontPrecip` to Weather FX root-owned modules in `DramalessAtmos`, shared by all supported voxel hosts.

## Preservation

`lib/voxel_atmos/WorldPrecip.lua`, `lib/ProceduralSnowField.lua`, and `lib/DistantFrontPrecip.lua` are unchanged from 8.1.58. The complete local snow population, fixed-world anchor streaming, MAX-setting virtualization and snow motion therefore remain intact.

## Validation

The 8.1.59 regression verifies remote snow remains present before local onset, fades continuously during takeover, disappears when the broad local field is established, blizzard follows the same rule, and rain remains unchanged. The test also requires both CPU and GPU distant paths to use the same handoff and requires the private GPU backend to resolve as Weather FX-owned.
