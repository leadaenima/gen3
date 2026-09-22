# Weather FX 8.1.26 — Celestial Realism / Player Experience Repair

Weather FX 8.1.26 is built from 8.1.25. It fixes the player-visible regression where the sun and moon could degrade into smooth center-bright/edge-dark discs and strengthens the low-sun visual experience without reducing weather quality.

## Sun and moon
- The analytic body shader retains procedural solar granulation, faculae and sunspots plus lunar maria, crater relief, highlands, earthshine and physical phase/eclipsing.
- Limb shading is restrained so surface detail survives at gameplay scale instead of reading as a generic shaded sphere.
- Hosts that reject the analytic body shader now receive a dense textured CPU fallback rather than the old plain radial disc.
- The 2D celestial path uses the same detailed body renderer when available and only retains the legacy disc as a last-resort safety fallback if the detailed authority itself fails.
- Body diagnostics record whether the analytic shader or detailed CPU fallback actually rendered and retain the shader error string when compilation is refused.

## Direct-look sun optics
- Faint solar optical response begins around 18 degrees from the sun instead of appearing abruptly inside the old 7.5-degree cone.
- God-ray, warm sensor response and whiteout ramps are staged independently; strong whiteout remains concentrated near direct gaze.
- Cloud transmission, body visibility and world-depth blocking still attenuate or suppress the effect.

## Sunrise and sunset
- Fixed the physical atmosphere band interpolation direction: sky colour belongs at the zenith and horizon scattering belongs at the horizon.
- Broadened low-sun golden-hour strength and added a stronger warm horizon while preserving a cooler upper sky.
- No changes to day length, sun/moon orbit timing or Weather Duration.

## Player-experience / code-bug audit
- All 61 settings remain registered, round-trip every declared choice, and retain live runtime consumers.
- 2D weather style, strict 3D precipitation/compositor, catalogue, fog ownership, live quality/intensity, world-space precipitation and indoor-audio suites are retained.
- Compatibility, performance, shadow-engine and Lua/LÖVE sandbox gates remain green.

## Quality contract
This release does not reduce particle counts, cloud counts, star/constellation/planet populations, draw distance, weather coverage, quality tiers or shadow quality. 8.1.24's zero-quality-loss performance architecture and 8.1.25's constellation fixes are preserved.
