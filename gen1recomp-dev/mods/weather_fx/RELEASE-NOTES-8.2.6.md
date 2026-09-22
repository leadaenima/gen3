# Weather FX 8.2.6 — All-Weather Phone + MAX Performance Qualification

Built directly from exact Weather FX 8.2.5. This release applies the same architecture-level performance discipline used for 3D snow to the rest of the 3D weather stack while preserving the 8.2.5 snow density multipliers and all established visuals.

## Runtime changes

- **Rain:** every nonzero logical rain field uses the proven procedural GPU visual renderer when available. Low-density fronts no longer remain on the legacy CPU-visible path. If GPU proof fails, CPU-visible rain is bounded by the existing quality `rain` budget before allocation.
- **Hail / sand / ash:** every nonzero noninteractive grain field uses the proven procedural GPU visual renderer when available. Failed GPU ownership is bounded by the existing quality `grain` budget. Leaves/debris stay physical for gameplay collision/settling.
- **Shared precipitation shader:** the instanced carrier changes from six duplicated triangle vertices to four unique triangle-strip vertices; deterministic hash, hail/sand wander and storm-band modulation are trig-free; the ash fragment silhouette no longer uses `atan`, `length`, or angular sine work.
- **Wet-weather reflections:** nearby puddle descriptors use reusable bounded pools, removing repeated table allocation from reflected-character scans.

## Audited and deliberately unchanged

The deep audit re-exercised the existing fast paths for 3D snow, cloud bank/RAVE clouds, fog, water, tornadoes, lightning, RAVE lasers, battle weather persistence, celestial rendering, rain movement/edge continuity, sand pitch behavior, leaves, host compatibility and the general 3D pipeline. These systems remain unchanged where their existing bounded/cached architecture passed.

No quality-tier effect is silently disabled to obtain these gains. MAX keeps authored logical effects; low-tier and compatibility paths are bounded rather than allowed to explode into world-scale CPU simulation.

## Qualification

See `WEATHER-FX-8.2.6-FINAL-AUDIT.md`, `WEATHER-FX-8.2.6-FINAL-QUALIFICATION.md`, and the external validation record for exact final package results.
