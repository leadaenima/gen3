# Weather FX 8.1.45 — Voxel Nexus Exclusive Water + VOID Performance

## Why this release exists

Weather FX 8.1.44 closed the remaining duplicate-relief path on the current public Battle Art host. Voxel Nexus 2.0.12 uses the same legacy `BATTLE_ART_VOXEL_FORK` id but has an additional realistic-water layer that changes the final model transform, plus a very large synthetic VOID horizon that was still being sent through an expensive second reflective water transaction.

The two player-visible symptoms are independent: old/native-looking water can remain visible around the Weather FX surface, and `VOID FILL = WATER` can add substantial GPU/frame-copy pressure even when the authored map water itself is inexpensive.

## Root cause 1 — curved prepass and reflective pass used different water heights

Voxel Nexus `VoxelScene.drawWater` deliberately draws water twice when world curvature is enabled: first through `Voxel3D.draw` to establish the water depth, then through `Water.draw` for the reflective surface. Those two submissions must use the same model transform.

Voxel Nexus' bundled `realistic/WaterEngine.lua` wraps `Water.draw` and adds its own `tideOffset()` model translation. Weather FX already bakes its connected-water tide into the replacement model. The curved prepass therefore received **Weather FX tide**, while the reflective pass could receive **Weather FX tide + Voxel Nexus tide**. Once those surfaces separate, the lower depth/prepass surface can show through at crests, edges or camera angles and read as old water underneath the replacement.

8.1.45 capability-detects the Nexus-only `_trainSource` + `realisticWorld.WaterEngine.tideOffset` seam. After successful Weather FX ownership, and only for the duration of that owned water transaction, the Nexus additive model-space tide returns zero. The exact original function object is restored immediately afterward, on ORIGINAL mode, on failure and on invalidation/hot reload. Weather FX remains the sole tide owner while Nexus still provides its reflection/depth shader.

## Root cause 2 — the far VOID ocean paid for a second FULL water pass

The complete outer VOID sea is a presentation-only holed mesh extending to the host's world-fill horizon (up to 32,768 world units). 8.1.44 already limits expensive CPU deformation to a near belt and uses distance-adaptive topology, but the bridge still submitted that far sea as a separate call to Voxel Nexus `VoxelScene.drawWater` before submitting the finite/authored replacement list.

On Voxel Nexus, each call can perform a curved depth prepass, a framebuffer/depth copy and the FULL screen-space reflective water shader. The outer sea can cover a large fraction of a first-person frame, so doing a separate FULL reflective transaction for the far horizon is high-cost fragment work even though its far geometry is intentionally coarse.

8.1.45 keeps the same physical outer mesh and the same near-belt 3D deformation, but on **Voxel Nexus only** draws that synthetic far horizon once through the already-bound scene shader. This avoids the second `beginWater`/depth-copy/SSR transaction. The finite **96px VOID handoff**, all cartridge/authored lakes/rivers, translucent ponds and their near water remain in the normal replacement list and retain the full Nexus reflective pass.

Other voxel hosts retain the previous reflective outer-sea path, and any Nexus fast-path failure falls back to that path. `WATER STYLE = ORIGINAL` remains an untouched native handoff.

## Exact Voxel Nexus source contract checked

Qualification used the preserved exact Voxel Nexus 2.0.12 package (`VOXEL_NEXUS-2.0.12-STADIUM-PRIVATE.zip`). The contract test checks its actual `lib/Water.lua`, `lib/VoxelScene.lua` and `lib/realistic/WaterEngine.lua` implementation: structured `_trainSource`, native `WAVE_HEIGHT = 5`, curved raw-model depth submission, reflective `Water.draw`, and the `composeTide(model)` wrapper driven by `tideOffset()`.

## Dedicated regression

`tests/voxel_nexus_water_8145_test.lua` proves that:

- Voxel Nexus is identified independently from public Battle Art despite the shared mod id;
- the bundled Nexus model-space tide is zero only inside Weather FX ownership and exact function identity is restored afterward;
- hot-swapped WaterEngine instances are captured/restored independently;
- successful physical ownership still zeros native geometric `WAVE_HEIGHT`;
- the 32K synthetic VOID horizon uses exactly one scene-shader mesh submission and invokes neither host `Water.begin` nor host `Water.draw`;
- near/authored water remains a separate reflective replacement path;
- non-Nexus hosts and fast-path failure retain the older reflective fallback.

## Preserved behavior

8.1.44 public Battle Art ownership remains unchanged. No water topology density, physical wave amplitude, shoreline deformation, foam, rapid, reflection quality on authored/near water, pond/fish behavior, tide range, ice behavior, Surf presentation, collision authority, cloud/celestial population, constellation brightness, aurora, snowstorm or storm-front quality is reduced.
