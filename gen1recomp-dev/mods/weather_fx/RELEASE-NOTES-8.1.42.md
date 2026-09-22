# Weather FX 8.1.42 — Winter Snowstorms + Research-Grounded Aurora

## Why this release exists

Winter already biased the weather catalogue toward snow, blizzard, sleet and thundersnow, but two player-visible gaps remained: distant frozen fronts still reused a rain-curtain presentation, and the winter night sky had no auroral system. 8.1.42 closes both without weakening the 8.1.41 reachable-front engine.

## Research-grounded aurora, not a green sky ribbon

The aurora morphology was designed from NASA/NOAA reference material before implementation. The renderer follows the characteristics that matter visually:

- aurora are thin luminous **sheets / curtains**, often horizon-scale, with folds, rays, bands and veils rather than opaque fog;
- pale oxygen green is the dominant visible body; stronger events can show a lower nitrogen purple/blue fringe and a rarer higher oxygen-red cap;
- structure continually evolves, but quiet arcs can remain coherent for minutes instead of boiling like fire or flapping like a cloth flag;
- strong displays can expand overhead, where field-aligned rays converge in perspective into a corona-like form;
- aurora are above ordinary weather clouds, so cloud banks must occlude them; moon and artificial light lower apparent contrast without changing the aurora's intrinsic emission.

Weather FX makes aurora **strongly winter-weighted**, while every spring, summer and autumn night receives an independent deterministic **5% natural aurora chance**. Physically, aurora can occur year-round; winter mainly provides longer darkness for viewing. The off-season 5% roll is a gameplay-frequency rule, not a change to the researched auroral morphology.

## Aurora implementation

`lib/Aurora.lua` is a bounded celestial-vault system, not a camera overlay. Each game night has a deterministic event plan so save/reload cannot reroll the sky. Winter uses the high-frequency seasonal schedule; outside winter, a separate stable `< 0.05` nightly roll supplies the requested 5% chance in spring, summer and autumn. Eligible nights vary from quiet to active to storm-class displays. The event grows and fades over a multi-hour night window rather than popping on/off.

The 3D path builds 2–4 parallel thin curtain sheets with 72 horizontal segments × 10 altitude layers per sheet. Irregular multi-scale fold fields deform the sheet slowly; narrower independently evolving field-aligned ray bundles reorganize faster without random per-frame teleporting or a repeating sine-ribbon pattern. Strong events extend to ~88° elevation so the same spherical geometry naturally becomes corona-like overhead. The projected voxel fallback consumes the same world-direction topology rather than substituting a flat sprite.

Colour is altitude-structured: dominant pale oxygen green, lower purple/blue nitrogen on energetic displays, and high red oxygen only as activity rises. Alpha remains intentionally translucent under additive blending so several sheets create depth without becoming neon walls.

Aurora respects **CELESTIAL EVENTS**, season-weighted nightly eligibility, astronomical night visibility, live cloud transmission, moonlight and BuildingLight contrast. Terrain/buildings/NPCs and the later volumetric cloud pass retain occlusion authority because the aurora is submitted in the same far-depth celestial stage as the star vault.

## Reachable winter snowstorms

The 8.1.41 StormCells engine already supports snow-channel weather and guarantees leading-edge arrival. 8.1.42 gives frozen fronts their own presentation family:

- `SNOW_LIGHT` remains a gentler snow curtain;
- `BLIZZARD` becomes a dedicated wind-driven whiteout morphology;
- `THUNDERSNOW` uses the same blizzard wall while preserving real remote lightning/thunder authority;
- severe frozen fronts use five overlapping wind-sheared precipitation bands plus a bounded ground-hugging blowing-snow veil instead of three recoloured vertical rain cards;
- the distant shader uses diagonal multi-frequency drift structure for blizzard snow, so it reads as blowing snow rather than white rain streaks.

No second weather simulator was added. These snowstorm visuals consume the existing world StormCell identity, size, motion, leading edge, lifetime and handoff.

## Preserved systems

8.1.41 reachable cell/regional/broad/synoptic storm fronts are unchanged. 8.1.40 exclusive VOID-water handoff remains preserved. Authored ponds, physical water, ice, SnowPack, lightning, tornadoes, celestial bodies, constellations, seasons, battle/gameplay safety and existing settings continue to use their prior authority paths.
