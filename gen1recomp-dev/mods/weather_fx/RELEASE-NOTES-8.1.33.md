# Weather FX 8.1.33 — Professional Physical Water

8.1.33 is built directly from the exact 8.1.32 baseline. Its purpose is player-facing: connected water must no longer read as a flat blue square simply because the old reflective/relief shader was mathematically active. The structured Voxel Realism path now owns a **real tessellated 3D surface** whose vertices physically rise, fall, and move laterally.

## What changed

- **Actual 3D wave geometry.** Connected liquid bodies are tessellated into an indexed dynamic mesh. Large-scale wave silhouette comes from world-space vertex displacement, not a screen-space blue texture or tiny UV ripple.
- **Gerstner-inspired crest motion.** The existing wind-aligned spectrum is reshaped into a dominant swell plus aligned harmonics and oblique cross trains. Bounded horizontal orbital displacement gives strong crests a forward lean without allowing the mesh to self-intersect.
- **Real crest/trough range.** The surface is centered on the hydrosphere tide datum, so troughs fall below mean water level while crests rise above it. Calm lakes retain visible natural heave instead of collapsing to an almost-flat sheet.
- **Exact shoreline ownership.** Horizontal motion is pinned to the cartridge-authored shoreline and blended to full strength inward. The wave surface can move vertically at the bank, but it cannot slide underneath land or rewrite collision.
- **Water-body behavior.** Connected topology is classified as POND, LAKE, RIVER, or SEA from the cartridge water mask. Small ponds remain gentler, broad lakes keep rolling heave, boundary-exposed bodies can build larger swell, and elongated narrow channels expose a rapid/flow axis.
- **Whitewater.** Strong crests can emit broken whitecap geometry. The strongest crests receive raised, multi-segment foam lips whose last segment folds forward/down, producing a visible curl from low and first-person camera angles. River channels generate aligned white rapid streaks, and impact-facing shoreline edges generate breaking foam.
- **Surf/player wave riding.** Presentation-only bob samples the same rendered crest field as the water mesh. The player's gameplay X/Z coordinates, tile collision, Surf state, triggers, warps, and progression remain untouched.
- **Reflection preserved.** Voxel Realism's mature reflective water shader remains the reflection/material layer. In the physical-mesh path its old artificial height slab is disabled so relief is not applied twice, while its wave-normal/reflection response remains driven by the same spectrum.
- **Fail-open compatibility.** If a structured dynamic mesh cannot be created, the entire frame falls back to the proven 8.1.32/8.1.31 reflective-relief path instead of mixing two incompatible displacement modes.

## Performance architecture

The dynamic topology is cached and reused. Small water uses a 4-world-pixel grid; broad bodies use an 8-world-pixel grid, which still provides roughly ten geometric samples across the dominant 78-pixel swell while reducing large-body vertex/trigonometric work by about four times versus a 4-pixel grid. Steady frames update the existing stream mesh instead of rebuilding water topology. The 8.1.32 cached dependency/transform hot path remains intact.

This release does **not** reduce rain/snow/blizzard/hail/sand/debris/ash populations, stars/planets/constellations, cloud radius, StormCells, water-body count, ice quality, SnowPack coverage, draw distance, shadows, or any player setting range.

## Executed water validation

`tests/professional_water_8133_test.lua` executes the new renderer against LÖVE-style mesh stubs and verifies all of the following:

1. lake, river, and sea morphology classification;
2. calm-lake heave remains visible;
3. physical indexed water ownership;
4. thousands of real 3D vertices/indices rather than one flat quad;
5. no double application of the old relief height slab;
6. substantial vertical crest-to-trough relief;
7. real horizontal orbital motion;
8. shoreline pinning;
9. whitecaps;
10. raised/folded curling crest lips;
11. directional river rapids;
12. shoreline breaking foam;
13. cached mesh reuse;
14. traveling wave crests;
15. Surf/player upward riding on a sampled crest; and
16. zero gameplay-coordinate mutation from bobbing.

The dedicated gate is **18/18 PASS**. The inherited 8.1.32 hot-path, 8.1.31 rolling-wave/WATER STYLE, 8.1.30 progressive-ice, and 8.1.29 connected-hydrosphere suites remain mandatory in the 8.1.33 release runner.

## Visual qualification

The exact new renderer was also executed through a LÖVE 11.5 3D validation scene at high and low camera angles. The low-angle lake capture visibly shows a non-planar waterline, rolling raised crests, troughs, broken whitecaps, and raised curl geometry. A calm-lake capture still has meaningful 3D heave without turning every pond into an ocean. The river capture shows directional white rapid streaks rather than generic lake foam.

These validation scenes are renderer evidence, not photorealistic marketing mockups. The target remains a professional stylized voxel-water presentation appropriate to Weather FX rather than photographic water.
