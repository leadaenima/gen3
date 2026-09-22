# Weather FX 8.2.1 Final Audit

## Scope
8.2.1 is a targeted 3D snow performance release built directly from exact 8.2.0. Runtime behavior outside `lib/ProceduralSnowField.lua` is intentionally unchanged.

## Root cause
8.2.0 successfully removed the moving SNOW/BLIZZARD field origin, but its periodic nearest-copy selection introduced costly per-vertex division/floor work into a renderer that can execute 600,000 snow vertices for 100k SNOW and 1.2 million for 200k BLIZZARD. The inherited renderer also repeated frame-constant patch normalization/division and sine-based random hashing inside every vertex.

## Repair
- Four-vertex triangle-strip quad: 6 -> 4 vertex executions per flake, a 33.3% reduction with identical quad coverage.
- Periodic wrapping: normalized phase + `fract`, mathematically checked against the exact 8.2.0 equation over positive/negative world coordinates and multiple field spans.
- Frame constants hoisted to CPU once per draw: tile/fade reciprocals, patch/front frequencies, patch wind normalization, vertical field constants and fall scale.
- Fronts-OFF/uniform snow bypasses storm-band trig.
- Native GLSL3 path replaces sine random hashing with 32-bit integer avalanche hashing. At 200,000 IDs: 198,739 unique 24-bit outputs, maximum decile deviation 0.84%, lag-1 correlation -0.002579. Representative hA/hC/hF/roll input streams also remain within the test's uniformity bounds.

## Smooth-motion / quality boundary
No particle ceilings were reduced. No animation update interval was increased. No frame skipping, temporal decimation, motion snapping, render-distance reduction, simplified snow shape, or lower-quality player setting was introduced. SNOW remains 100,000 at the authored ceiling and MAX BLIZZARD remains 200,000. The presentation clock advances every render frame.

## Source qualification
- mobile snow performance: 15/15 PASS
- hash quality: 8/8 PASS
- inherited cloud/RAVE/snow: 16/16 PASS
- inherited snow motion: 13/13 PASS
- maintained developer sweep: 118/118 PASS
- test_mod.py --lua: 195/195 PASS
- revision gate: 80/80 PASS
- source runtime Lua compile: 129/129 PASS
- exact-package replay: required after freeze and published in external validation evidence

## Truth boundary
This environment cannot measure FPS on the user's exact low-powered phone or capture its live framebuffer. The release therefore claims concrete workload reductions and executable invariants, not a fabricated device FPS result.
