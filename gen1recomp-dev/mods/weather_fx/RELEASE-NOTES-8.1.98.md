# Weather FX 8.1.98 — RAVE Cloud + Snow Continuity Repair

Built directly from exact Weather FX 8.1.97.

## RAVE cloud bank

RAVE now has a physically denser volumetric ceiling: its cloud span, puff/lobe population and sealed-deck overlap are increased only for RAVE. A dedicated bounded world-space overhead admission/fade keeps nearby sealed cloud volumes alive when their centres leave the normal projection band during a straight-up camera pitch. This fixes the bank thinning/disappearing when looking upward without globally weakening cloud culling for ordinary weather.

## Snow walking continuity

The procedural snow field still uses immutable world anchors and the same constant authored particle count during handoff. The old anchor cell, however, could be as large as 256 world units, allowing the field centre to lag the player by up to 128 units. Walking toward that edge could expose a sparsely populated leading section until the new anchor completed its handoff. 8.1.98 tightens the snow anchor cell to 4% of the active radius, capped at 24 world units, so maximum centre lag is 12 units. No extra snow instances or doubled handoff fields are introduced.

## Blizzard one-pixel/fountain guard

The 8.1.90/8.1.91 distant-front retirement remains in place. 8.1.98 closes one remaining seam: if the snow channel briefly publishes zero while the authoritative current weather is still SNOW/BLIZZARD-family, the stale finite distant snow slab now remains retired instead of returning for a frame as a perspective-compressed point/fountain. A genuinely distant incoming snow front remains visible when the current local weather is clear. Rain, fog and lightning front ownership are unchanged.

## Regression proof

The new 8.1.98 regression exercises real cloud descriptor admission, snow anchor geometry and distant-snow ownership. It passes 12/12 on 8.1.98; exact 8.1.97 fails 8/12, proving the checks are sensitive to these fixes rather than decorative. Existing RAVE, cloud-pitch, snow-motion, snow-fountain, snow-virtualization and full-render-distance regressions remain required.
