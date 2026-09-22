# Weather FX 8.1.67 — Final Qualification

**Decision: PASS — release-ready after exact frozen-package replay.**

The release is based directly on exact Weather FX 8.1.66 and changes exactly nine runtime files: `config.lua`, `lib/CelestialBodies.lua`, `lib/CelestialRenderer2.lua`, `lib/Config.lua`, `lib/DramalessAtmos.lua`, `lib/Settings.lua`, `lib/SnowPack.lua`, `lib/SnowSurfacePaint.lua`, and `lib/Tornado.lua`.

The release fixes the live floating-snow/ledge-support defects, restores the requested 90-second 2D Gale tornado opportunity with a 10% normal relocation roll, exposes a shared tornado-frequency setting, prevents screen-locked 2D sun/moon behavior under voxel cameras, and adds an independent celestial presentation selector so 2D weather can coexist with 3D celestial rendering.

Exact package byte count/SHA-256, ZIP integrity and fresh-extraction replay are recorded externally in `weather_fx-core-8.1.67-validation.txt` after the immutable archive is created.

Live framebuffer proof uses the preserved Gen1Recomp 0.2.53 / LÖVE 11.5 runtime, Pokémon Yellow test input and exact Voxel Nexus 2.0.17. Raw 1024×768 clear/falling/mid/heavy/melted frames and the live log are preserved externally alongside the release.


The complete maintained-runner command list is covered by a PASS-only monolithic prefix through 8.1.26 plus bounded continuation segments A/B through the final strict audits. The shell timeout itself is not counted as a pass.
