# Weather FX 8.1.51 — Zero-Upload Front Precipitation / Max-Settings Performance

Built directly from exact Weather FX 8.1.50.

## What changed

- **Remote front hydrometeors no longer rebuild a large CPU mesh every frame on supported hosts.** The same deterministic rain/snow/blizzard field is synthesized in the vertex shader from Weather FX's existing immutable `InstanceSeedBuffer`.
- **No particle reduction:** the shared remote-front budget remains exactly **9,000** particles at MAX quality, with the same per-front class floors and 6,500 per-front ceiling.
- **No handoff reduction:** the 8.1.50 **62%** remote/local precipitation overlap in `DistantWeather` is unchanged.
- **No morphology reduction:** rain fall/size/shear constants and snow/blizzard fall/size/gust constants match the 8.1.50 CPU formulas.
- **Indexed instance geometry:** one immutable four-vertex quad plus a six-index map is reused per particle, avoiding the six-vertex duplication common to a simple non-indexed instancing quad.
- **Allocation-flat steady state:** support/resource checks stop after initialization; uniform vector scratch records and the four possible per-front option records are reused instead of allocated each frame.
- **CPU fallback retained:** if instancing, shader creation, attribute attachment or a draw fails, Weather FX immediately uses the exact 8.1.50 CPU hydrometeor builder. Fog remains card/volume geometry and distant lightning remains world-space.

## Max-settings qualification

All **68 player-adjustable Weather FX controls** are validated simultaneously with the highest-load / fully enabled values. That profile includes MAX graphics, FULL textures/reflections/background detail, FAR effect distance, HEAVY weather strength, 200% rain, 500% snow/fog/sand/dust, raised 3D clouds, enhanced water, full battles/lightning/audio, 3D presentation, fronts ON with MAX reach, mesoscale ON/STRONG, 200% wind, and all optional world/celestial/gameplay effects enabled.

`PARTICLE LIMIT = TIER` is the true maximum-load value under `GRAPHICS QUALITY = MAX`: choosing the largest numeric override (`20,000`) would intentionally cap the larger authored snow/blizzard ceilings. With TIER selected, the MAX quality contract remains rain **12,000**, snow **100,000**, blizzard **200,000**, hail **45,000**, sand **43,200**, debris **3,600**, ash **10,800**, plus the complete celestial catalogue.

## Quantitative front hot-path result

At the 9,000-particle remote-front ceiling, 8.1.50's CPU path performs per frame:

- **36,000** hydrometeor vertex rows (4 per particle);
- **54,000** vertex-map index values (6 per particle);
- **36,000** deterministic sine-hash evaluations (4 per particle), plus fall/shear motion math;
- **252,000 float components = 1,008,000 bytes** of vertex-float payload before index/mesh-driver overhead.

8.1.51's supported-host production path builds **0** CPU hydrometeor rows and **0** hydrometeor index values per frame. A controlled 80-iteration two-front MAX-budget CPU-preparation benchmark was repeated three times: the old builder took **1.747–1.966 s**, while the instanced preparation path took **0.000473–0.000713 s** in the same `texlua` container (**99.96–99.98% less isolated CPU preparation time**). This is an isolated hot-path result, not a claim of whole-game FPS improvement or physical-GPU frame time.

## Preserved

- 8.1.50 seamless discrete 3D front precipitation and stable handoff identity.
- All 68 settings / 11 shallow categories.
- All authored weather populations and quality tiers.
- Water/waves/tides/ripples/ice/SnowPack.
- Clouds, world fronts, mesoscale weather, tornadoes and lightning.
- Sun/moon/stars/25 constellations/planets/aurora/events and world occlusion.
- Audio, battles, encounters, seasons, day/night and gameplay-speed authority.

See `PERFORMANCE-AUDIT-8.1.51.md` and `WEATHER-FX-8.1.51-FINAL-AUDIT.md`.
