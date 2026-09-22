# Weather FX 8.2.13 — MAX T-SNOW 3D Rebalance

This release fixes the MAX-quality 3D THUNDERSNOW / T-SNOW presentation reported after 8.2.12: too much distant snow collapsed into a fuzzy white field while the space immediately around and above the player did not read strongly enough as a blizzard.

## What changed

- T-SNOW now keeps a fully dense player/overhead core, then thins its visible particle population steeply with distance.
- Full 3D precipitation reach is preserved. The far edge remains nonzero rather than ending at a visible cutoff.
- The near detailed-snow shell is widened and densified so large flakes occupy the local and overhead storm volume.
- The extra detailed-card work is hard-capped; logical snow population and CPU interaction/accumulation work are unchanged.
- Ordinary SNOW and BLIZZARD use their existing 8.2.12 profiles unchanged.

## Live visual qualification

The fix was exercised at GRAPHICS QUALITY = MAX, 3D WORLD, THUNDERSNOW, HEAVY weather strength, 100% snow amount and 100% 3D precipitation distance on real cartridge-backed runs:

- Pokemon Crystal / Gen2Recomped 0.7.40 built-in `Gen2Recomped-DramaticShapes` host.
- Pokemon Yellow / Gen1Recomp 0.2.53 + Battle Art Voxel Fork 1.10.4.

Both hosts reported 300,000 live procedural snow identities with healthy 3D submission. Forward and upward first-person framebuffer captures verify the intended redistribution: the thick distant fuzzy band is reduced while distinct flakes and large detailed crystals occupy the near/overhead volume.

## Compatibility

8.2.12 native Gen2 host support, six-edition targeting, weather/lightning behavior, full render-distance contract and existing snow accumulation/gameplay behavior remain intact.
