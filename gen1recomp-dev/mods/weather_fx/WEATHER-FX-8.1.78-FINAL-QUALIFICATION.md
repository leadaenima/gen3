# Weather FX 8.1.78 Final Qualification

**Status: QUALIFIED by exact-package executable/runtime gates, pending user-host visual confirmation.**

8.1.78 changes fronts-OFF rain from a locally streamed radial field to an absolute rendered-world grid. At 100% weather distance, the field covers the complete live voxel render window at the exact voxel far distance. Lower distance settings remain weather-only reductions.

The new regression passes 14/14 and exact 8.1.77 fails 10/14 as expected. Inherited rain continuity, precipitation streaming, world-space, virtualization, performance, 3D pipeline, feature integrity, compatibility and package gates must all remain green on the exact final archive before release.

No fresh live-game framebuffer is claimed for this release.
