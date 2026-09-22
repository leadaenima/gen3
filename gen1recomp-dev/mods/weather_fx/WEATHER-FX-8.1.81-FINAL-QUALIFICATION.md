# Weather FX 8.1.81 Final Qualification

**Status: QUALIFIED for package freeze.**

Weather FX 8.1.81 is a zero-quality-loss CPU/GPU/RAM/VRAM efficiency release built directly from exact 8.1.80.

Release gates passed:

- current resource-efficiency regression 26/26;
- required negative control against exact 8.1.80;
- tornado 3D 38/38, waterspout 5/5 and remote culling/re-entry 4/4;
- current water ownership/style/safety regressions;
- revision 80/80;
- performance invariants 66/66;
- 3D pipeline 117/117;
- feature integrity 505/505;
- voxel-host contract 27/27;
- sandbox scan of 125 runtime Lua files;
- maintained Lua suite 191/191;
- `texluac` compile of all 125 runtime Lua files;
- inherited 8.1.71–8.1.78 rendered-world precipitation/front/distance gates.

Deterministic equivalence proof confirms identical water reference/checksum output and zero numeric tornado geometry delta against exact 8.1.80. Isolated benchmarks show materially lower tornado CPU/allocation cost and lower water-wave CPU cost; these are not live-device FPS claims.

Wind-driven water, tornado cloud descent/attachment, particle counts, weather distances/front ownership, animation timing, settings and assets are preserved.

No fresh live framebuffer was captured, so qualification covers source/runtime/package contracts and deterministic output equivalence, not a claim of live visual inspection.
