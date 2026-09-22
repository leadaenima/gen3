# Weather FX 8.1.80 Final Qualification

**Status: QUALIFIED for release.**

Weather FX 8.1.80 is a zero-quality-loss 3D atmosphere runtime optimization built directly from exact 8.1.79.

Release gates passed:

- current 8.1.80 optimization regression 29/29;
- required negative control against exact 8.1.79;
- revision 80/80;
- performance invariants 66/66;
- 3D pipeline 117/117;
- feature integrity 505/505;
- voxel-host contract 27/27;
- sandbox scan of 125 runtime Lua files;
- maintained Lua suite 191/191;
- `texluac` compile of all 125 runtime Lua files;
- inherited rendered-world rain, turn/ledge/walk continuity, fronts-OFF continuity, streaming and render-distance gates.

The release preserves exact particle caps, weather distance/front ownership, cloud/frustum logic, settings and assets.

No live framebuffer was captured; qualification therefore covers source/package/runtime contracts, not a claim of human visual inspection.
