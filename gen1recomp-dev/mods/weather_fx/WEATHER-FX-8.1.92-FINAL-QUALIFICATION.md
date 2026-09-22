# Weather FX 8.1.92 Final Qualification

**Status: qualified for packaging, pending user-side visual confirmation on the real Battle Art voxel host.**

The reported defect is addressed at its runtime source: fronts-enabled 3D snow no longer inherits the old 750-unit regional ceiling. With **3D WEATHER DISTANCE = 100%**, the snow field radius follows the current voxel render distance exactly, so walking through the rendered world does not cross a Weather FX snow-radius boundary before the host far plane.

The player-facing 25/50/75% choices remain deliberate reductions. Quality controls particle population rather than silently shrinking snow reach. Rain/hail fronts behavior is unchanged.

Evidence:
- 8.1.92 focused snow-distance regression: 8/8 PASS.
- Exact 8.1.91 negative control: 6 corrected checks fail as expected.
- Maintained developer sweep: 102/102 programs PASS.
- 8.1.91 one-pixel snow ownership and Battle Art water ownership tests remain in the maintained sweep and pass.

No fresh framebuffer capture is claimed.
