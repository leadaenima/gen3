# Weather FX 8.1.91 Final Qualification

**Status: installable hotfix qualified by source/runtime regression gates; live visual confirmation pending on the user's Battle Art host.**

8.1.91 is built directly from exact 8.1.90 and changes only three runtime Lua files. It addresses the two reported regressions without changing Battle Art itself.

### Snow

Player-local 3D snow becomes the exclusive nearby snow presenter once the live local snow channel is above 0.02. The finite distant snow/blizzard slab remains available only while snow is genuinely distant. This removes the partial-overlap state that can perspective-compress into a one-pixel snow fountain.

### Battle Art water

Current public Battle Art's Water export includes `_trainSource`, so that symbol is no longer treated as a Voxel Nexus signature. Voxel Nexus is identified from its additional WaterEngine tide seam. During Weather FX physical-water ownership, host geometric relief is forced to zero and the host Water shader is invalidated once when ownership changes, preventing a previously compiled Battle Art relief heightfield from being drawn on top of the Weather FX surface. Battle Art continues to provide its reflection/depth material on the replacement Weather FX geometry.

### Qualification gates

- Focused snow/water compatibility suites: PASS.
- Current Battle Art compatibility regression: PASS.
- Voxel Nexus regression: PASS.
- Developer sweep: 101/101 programs PASS.
- Runtime Lua compile: 128/128 PASS.
- Deliberate negative controls: both corrected behaviors fail when reverted.

No live framebuffer claim is made for this build environment.
