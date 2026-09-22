# Weather FX 8.1.79 Final Qualification

**Status: QUALIFIED by executable/source and exact-package replay gates, pending user-host visual confirmation.**

8.1.79 is a zero-quality-loss runtime cleanup of exact 8.1.78. The release reduces avoidable Lua allocations and redundant shadow/cloud/scheduler work while preserving the approved rendered-world rain, 3D WEATHER DISTANCE, front ownership, precipitation budgets, snow accumulation/repaint, cloud-bank behavior, celestial geometry/brightness and continuous shadow projection.

The dedicated 8.1.79 regression passes 25/25; exact 8.1.78 fails 14 of those 25 checks as expected. Broad revision, performance, 3D pipeline, feature integrity, LuaJIT and Lua headless gates remain green.

The final archive must be extracted and replayed through those same gates after freezing. Package identity is published separately in the SHA-256/validation artifacts so the archive does not need to contain a self-referential hash.

No fresh live-game framebuffer is claimed for this release.
