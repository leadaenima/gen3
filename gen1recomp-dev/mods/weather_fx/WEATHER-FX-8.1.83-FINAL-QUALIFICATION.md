# Weather FX 8.1.83 — Final Qualification

**Status: QUALIFIED BY DEVELOPER/EXACT-PACKAGE TESTING**

Release blockers addressed: 3D snow stepping; player-local hail/sand/ash/black-ash coverage with fronts OFF; 2D battle weather leaking into 3D world-backed battles; sticky WEATHER OFF; missing direct-look 3D sun glare.

Acceptance gates:

- full developer sweep: 83/83 programs
- release-specific regression: 49/49
- exact 8.1.82 negative control: expected failure, 42/49 new checks fail
- complete authored 2D weather style matrix: PASS
- 3D precipitation ownership/world-space/render-distance suites: PASS
- snow motion/virtualization/intensity/accumulation suites: PASS
- clouds/fronts suites: PASS
- lightning/NPC strike/tornado/waterspout/pickup/transfer suites: PASS
- celestial/sun/occlusion suites: PASS
- water/wind suites: PASS
- audio/battle/seasons/gameplay/debug suites: PASS
- all current settings suites: PASS
- revision/performance/3D/feature/host/sandbox/maintained suites: PASS
- runtime Lua compiler: 125/125

The frozen install package is accepted only if ZIP integrity and the same exact-package developer-sweep replay pass; this release was not preserved until those gates completed successfully.

No fresh human framebuffer/device test is claimed.
