# Weather FX 8.1.19 — Weather-owned Shadow Engine Release Audit

## Scope

8.1.19 starts from the preserved Weather FX 8.1.18 package. The intentional executable delta is restricted to:

- `lib/DramalessAtmos.lua` — installs Weather FX shadow ownership into compatible voxel hosts in memory.
- `lib/WeatherShadowMap.lua` — new Weather FX-owned shadow-map implementation.

The 8.1.19 runtime freeze proves every other executable Lua/compat file and shipped asset remains byte-identical to the approved 8.1.17 runtime carried by 8.1.18.

## Shadow architecture

Weather FX no longer wraps the host's shadow cache/projection after the host has already allocated and begun its own map. It replaces the methods on the host's existing public `ShadowMap` table in memory, preserving the caster interface already consumed by the voxel scene.

Retained caster/receiver contracts:

- terrain/buildings/trees/ledges/props continue through the host terrain caster pass;
- neighboring-map meshes keep their model transforms;
- water surface caster geometry remains submitted;
- flowers, authored figures, NPCs, the player, Stadium/provider models keep their existing caster paths;
- caster `model` matrices are applied by the Weather FX writer;
- red+green preserve the host's packed ~16-bit linear depth;
- blue preserves the host sprite/model-caster classification used by water;
- `snug()` preserves the host caster contact-shadow contract and uses the light direction committed to the currently sampled map.

## Stability/performance changes

- Rotating celestial motion is never snapped with `floor(lightSpace / texel)`. The light projection changes continuously with sun/moon direction.
- Camera anchoring is separate from celestial motion and quantized at 1/16 world pixel.
- The host's coarse 1/128 KX/KZ signature fields are removed only from the shadow-cache identity when the expected numeric signature prefix is proven. All camera/geometry/pose/model identity remains authoritative.
- Recast is based on accumulated displacement of a maximum-height caster's shadow endpoint: HIGH 0.04 world px, MEDIUM 0.07, LOW 0.12, POTATO 0.16.
- While the map is reused, the receiver keeps the committed light direction so `sunVP`, `sunModel/snug`, bias and texture never describe different light frames.
- `available()` never allocates or resizes a shadow canvas.
- Resolution can grow to the next supported rung when needed, but does not shrink repeatedly during a live session.
- Color/depth targets share the host PixelCanvas one-physical-texel DPI rule where available.
- Explicit depth formats are tried first (`depth24`, `depth24stencil8`, `depth32f`, `depth16`) with implicit-depth fallback.
- A failed caster/GPU pass restores graphics state and is not published as a valid map.

## Executed proof

Focused shadow gates:

- Weather-owned shadow runtime: **26 / 26 PASS**.
- Shadow architecture/static contract: **12 / 12 PASS**.
- Production projection monotonicity: **11 / 11 PASS**.
- 5,000-sample moving-light stress: reproduced host projection had **86 reverse steps**; Weather FX projection had **0**.
- Continuous celestial/shadow contract: **42 / 42 PASS**.
- Lua syntax: **116 / 116 runtime files PASS**.
- Love sandbox: **116 shipped runtime Lua files PASS**.

Preserved 8.1.18 regression wall:

- runtime freeze: **157 / 157** checks; exactly two intentional runtime deltas;
- manifest behavior freeze: **20 / 20**;
- semantic snapshot: **791 / 791** exact;
- config/quality snapshot: **304 / 304** exact;
- weather catalogue: **1,407 / 1,407**;
- celestial stress: **49,836 / 49,836**;
- wind stress: **282,245 / 282,245**;
- BuildingLight stress: **411 / 411**;
- night scheduler: **482,001 / 482,001**, with the frozen seed retaining 104 shower nights / 1,000;
- Weather-OFF cross-module contract: **15 / 15**.

Broader release gates:

- revision gate: **80 / 80**;
- maintained headless Lua suite: **181 passed / 0 failed / 0 skipped**;
- 3D pipeline integrity: **117 / 117**;
- voxel-host contract: **26 / 26**;
- benchmark: **26 / 26** plus **24 / 24** integration;
- settings descriptions: **1,335 / 1,335**;
- expanded constellations: **65 / 65**;
- aggressive compatibility: **0 HIGH findings**;
- strict full audit: **HIGH 0 / LOW 0** (three expected manual/live-engine items remain).

One inherited 8.1.13 test assertion still expected the superseded 1.00/.82 atlas constellation alpha. The test was corrected to accept the approved 8.1.17 midpoint .96/.73 runtime. No constellation runtime was changed.

## Validation boundary

This environment has no runnable Gen1Recomp/LÖVE framebuffer, so headless tests cannot truthfully prove subjective final shadow softness, Android/desktop driver presentation, or hot-unload behavior. The exact install ZIP is separately CRC/path/hash checked and re-tested after extraction. A normal in-game smoke test should specifically watch long building/tree/person shadows while walking and while the sun advances: they should move without the old hold/reverse/jump behavior.
