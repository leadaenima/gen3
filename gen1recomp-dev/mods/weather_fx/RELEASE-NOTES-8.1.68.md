# Weather FX 8.1.68 — Distributed Coalescing Snow Banks

## Fixed

- Removed the startup accumulation lines caused by the old 4-pixel 9×9 player-local aggregate lattice.
- Snow accumulation now ramps in gradually during the opening 45 seconds instead of rapidly building a ring/grid around the player.
- Aggregate snowfall samples are spread over a wide deterministic golden-angle field, keeping exact-support sampling bounded while avoiding straight rows and repeated local hammering.
- Overlapping same-surface snow patches now coalesce into one mass-preserving bank instead of rendering as separate stacked blobs.
- Mature banks grow broader and use a flatter interior with a soft perimeter slope so sustained snowfall reads as connected drifts.
- Footsteps no longer subtract persistent bank mass while a snow-family weather is still active; the footprint remains a temporary depression overlay and continued snowfall fills it naturally.
- Snow accumulation height is unchanged from 8.1.67: ground remains 3.60 world units, grass 3.20, and all raised/tree/thin-prop height caps are preserved exactly.

## Performance

- Aggregate exact-support sampling remains bounded and is now capped at 18 samples/second after ramp-up (lower during storm startup).
- Wider-bank clipping only probes to the current bank radius instead of sweeping to the maximum possible radius on every update.
- Coalescing is limited to a 3×3 cell neighborhood and reduces patch count as banks mature.
