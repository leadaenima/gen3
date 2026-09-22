# Weather FX 8.1.42 — Aurora Borealis Research Translation

## Research basis
The aurora renderer was designed from NASA and NOAA descriptions of discrete aurora rather than from generic game-ribbon references.

- NOAA SWPC describes evening aurora as one or more long east-west arcs, often bundled into tall rays that read as hanging curtains; activity is commonly strongest near local midnight.
- NASA aurora education material describes long narrow arcs and bands that kink, fold, swirl and ruffle like curtains, then break into rays and, during strong displays, a corona.
- NASA's Heliopedia distinguishes discrete aurora as bright thin bands with a definite lower border that can wave slowly or rapidly and take on curtain forms.
- NOAA Science On a Sphere identifies pale yellow-green atomic oxygen (557.7 nm) as the most common visible colour, high-altitude red atomic oxygen (630.0 nm), and blue-purple molecular nitrogen along lower ray edges.
- NASA/NOAA both note that aurora are not physically winter-only; they can occur year-round. Weather FX therefore keeps winter as the high-frequency gameplay season but gives every non-winter night a separate deterministic 5% natural-aurora chance. The 5% value is a gameplay-frequency rule; the visual model is unchanged by season.

## What this forbids
Weather FX must not implement aurora as:
- one flat camera-facing green quad;
- opaque neon fog;
- a perfectly periodic horizontal sine ribbon;
- a texture that rotates with the camera;
- an effect visible through opaque cloud, terrain or buildings;
- a constant winter sky tint.

## Renderer translation
The 8.1.42 implementation therefore uses:
- multiple parallel thin world-vault curtain sheets;
- a fixed world-north magnetic orientation instead of camera-facing geometry;
- a crisp lower edge and softer upper extinction;
- tall field-aligned ray columns embedded in the sheets;
- multi-frequency folds and ruffles moving on slower time scales than ray scintillation;
- horizon-scale arc spans, with stronger events extending toward the zenith so the same 3D topology creates a corona-like perspective overhead;
- altitude-ordered pale oxygen green, lower energetic nitrogen purple/blue, and rarer high oxygen red;
- low additive alpha so overlapping sheets create luminous depth without becoming solid neon walls;
- cloud-transmission, moonlight and nearby-building-light contrast attenuation;
- deterministic nightly quiet / active / storm strength classes and multi-hour rise/peak/fade rather than frame-to-frame random re-rolls.

## Winter weather pairing
Aurora is independent of snow precipitation. Winter storm fronts use the existing reachable StormCells world system and can carry SNOW_LIGHT, BLIZZARD or THUNDERSNOW. Severe frozen fronts render as wind-sheared multilayer snow walls plus low blowing-snow veils; they do not repurpose the aurora renderer or make clouds glow green.
