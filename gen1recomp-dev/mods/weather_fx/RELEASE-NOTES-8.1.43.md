# Weather FX 8.1.43 — Exact Constellation Peak Brightness

## Why this release exists

The 25-subject traced constellation catalogue was already using the shared `.96 / .73` landmark/trace hierarchy, but 8.1.25 also applied a second per-constellation density-energy gain. That made the actual maximum brightness depend on the drawing: sparse older subjects could saturate at full alpha while dense atlas subjects were trimmed as low as `0.672`. Different authored RGB tints widened the perceived difference further.

8.1.43 removes that contradiction. **Maximum unobstructed brightness is now a property of the constellation system, not of the source drawing.**

## Exact 25-subject brightness contract

- all 25 constellations use exactly `1.0` per-subject gain;
- primary/landmark stars retain the approved `0.96` alpha hierarchy;
- secondary trace stars retain the approved `0.73` alpha hierarchy;
- every constellation tint is minimally adjusted to the same Rec.709 display luminance of `0.82`;
- therefore every primary sample has the same unobstructed peak luminance contribution: `0.96 × 0.82 = 0.7872`;
- every secondary sample likewise resolves to `0.73 × 0.82 = 0.5986`;
- original source RGB values remain attached to every traced star for audit/reversibility.

The tint normalization does **not** turn the catalogue white. Darker hues move only as far toward white as necessary to reach the common luminance; brighter hues scale down uniformly. Pokémon-specific color identity is retained.

## What is deliberately unchanged

This release does not change constellation positions, anchor spreading, traced point counts, atlas geometry, billboard-size hierarchy, sky rotation, horizon handling, twinkle, cloud attenuation, building-light dimming, or terrain/building depth occlusion. Those effects still lower all constellations naturally. The equality guarantee applies at the shared maximum state: deep night, clear sky, and away from building light.

## Qualification

`CONSTELLATION-BRIGHTNESS-AUDIT-8.1.43.csv` enumerates every subject and proves the same target across the full 8,507-star traced catalogue. The dedicated executable regression checks every star, both brightness tiers, all 25 gains, and preservation of source colors.

8.1.42 winter snowstorms/aurora, 8.1.41 reachable storm fronts, 8.1.40 exclusive VOID-water ownership, authored ponds, Professional Physical Water, ice/SnowPack and prior gameplay safety are preserved.
