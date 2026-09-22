# Weather FX 8.1.92 — Full-Render-Distance 3D Snow Coverage

## Fixed: the player could reach the edge of the 3D snow field

Weather FX already had a **3D WEATHER DISTANCE** setting whose default is **100%**, but one old branch still treated snow differently when **WEATHER FRONTS** was ON: the snow volume was clamped to the inherited 750-world-unit front ceiling. On hosts rendering farther than that, the player could reach/see the end of the falling-snow disk and then watch a new field stream in.

8.1.92 removes that hidden fronts-ON snow ceiling. Falling 3D snow now resolves from the live voxel far distance in both fronts modes:

- **100%** = exact live voxel render distance.
- **75% / 50% / 25%** = explicit player-selected reductions of that live distance.
- WEATHER FRONTS may still shape snow patchiness and local density, but no longer shrinks the 100% physical snow volume.
- Quality/performance budgets may reduce the number of flakes; they do not shorten the 100% coverage radius.
- Rain and hail keep their existing fronts-ON regional/quality reach. This change is snow-only.

The procedural-snow preflight path now uses the same snow-specific far distance as the main WorldPrecip update, so the first proven GPU field and subsequent visible field agree on coverage.

## Preserved fixes

- 8.1.91 exclusive local-snow ownership that removes the remaining one-pixel/perspective-compressed snow fountain.
- 8.1.91 current Battle Art water capability disambiguation and host-relief invalidation.
- Existing rain/hail continuity, SnowPack, cloud/front, RAVE, tornado, lightning, celestial, battle and gameplay behavior.

## Qualification

- New 8.1.92 snow render-distance regression: **8/8 PASS**.
- Exact 8.1.91 negative control: **2/8 PASS, 6/8 FAIL**, proving the new test detects the old fronts-ON snow-radius behavior.
- Maintained developer sweep: **102/102 programs PASS**.
- No fresh real-host framebuffer/device session was available in this build environment; final eyes-on confirmation should be done in the user's Battle Art voxel setup.
