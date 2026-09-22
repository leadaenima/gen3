# Weather FX 8.1.51 — Final Release Audit

## Release identity

Weather FX **8.1.51**, "Zero-Upload Front Precipitation / Max-Settings Performance", is built directly from the exact preserved Weather FX 8.1.50 baseline.

The runtime change is deliberately surgical:

- existing runtime file changed: `lib/voxel_atmos/CinematicAtmos.lua`;
- new runtime module: `lib/DistantFrontPrecip.lua`;
- `lib/DistantWeather.lua`, `lib/Settings.lua`, `lib/Quality.lua`, `lib/voxel_atmos/WorldPrecip.lua`, and `lib/voxel_atmos/ConnectedWater3D.lua` remain byte-identical to 8.1.50.

## Performance repair

8.1.50's seamless-front fix correctly replaced painted distant rain/snow with discrete world-space hydrometeors, but the compatibility path could rebuild four CPU vertices and four deterministic sine hashes for every visible remote particle each frame. At the authored MAX remote-front ceiling of 9,000 particles that represents 36,000 CPU vertex rows, 54,000 index values, 36,000 sine hashes, and 1,008,000 bytes of vertex-float payload before driver/index overhead.

8.1.51 adds an indexed four-vertex hardware-instanced path backed by the existing immutable 8,192-entry `InstanceSeedBuffer`. Particle identity, front-depth distribution, lateral distribution, fall cycle, wind drift, rain streak dimensions, snowflake dimensions, blizzard shear/gust and alpha are reconstructed in the shader from the same deterministic family used by 8.1.50. The shared 9,000-particle ceiling and 62% remote/local handoff overlap are unchanged.

After initialization the supported-host path reuses one base mesh, one shader, the existing immutable seed buffer, bounded vector scratch, and up to four per-front option records. It avoids repeated capability/resource probes and does not rebuild/upload the 36,000-row hydrometeor CPU mesh. If instancing/shader/attribute/draw support is unavailable or fails, the exact 8.1.50 CPU hydrometeor builder remains the automatic fallback.

A controlled two-front MAX-budget 80-iteration benchmark was repeated three times. The 8.1.50-style CPU builder took 1.746663–1.966378 s; the 8.1.51 supported-host CPU preparation took 0.000473–0.000713 s, a 99.96–99.98% reduction in this isolated CPU preparation workload. This is not represented as a whole-game FPS or physical-GPU multiplier.

## Maximum-settings contract

All **68** Weather FX player controls are exercised simultaneously using their highest-load / fully enabled values. Manual `GRAPHICS QUALITY = MAX` remains scale 1.0 under severe sustained frame-pressure simulation. `PARTICLE LIMIT = TIER` is used because the numeric 20,000 override would intentionally cap authored snow/blizzard ceilings and is therefore not the true maximum-load configuration.

The simultaneous profile preserves the authored MAX ceilings:

- rain 12,000;
- snow 100,000;
- blizzard 200,000;
- hail 45,000;
- sand 43,200;
- debris 3,600;
- ash 10,800;
- complete star/planet/constellation/effect catalogue.

Fronts, mesoscale weather, raised 3D clouds, FAR effect distance, full reflections, Weather FX water, smooth sky, god rays, 200% wind, 200% rain, 500% snow/fog/sand/dust, battles, lightning, audio, tornadoes and optional world/celestial/gameplay effects are enabled together in the stress profile.

## Pre-freeze qualification

Completed from the candidate source tree before archive freeze:

- Lua syntax compile wall: **268/268** units PASS;
- Python syntax compile wall: **169/169** units PASS;
- 8.1.51 package surface: **27/27** PASS;
- 8.1.51 runtime freeze: **162/162** PASS;
- 8.1.51 performance release gate: **18/18** PASS;
- 8.1.51 instanced front renderer: **10/10** PASS;
- simultaneous max-settings stress: **10/10** PASS;
- inherited 8.1.50 front continuity: **9/9** PASS;
- feature integrity: **498/498** PASS;
- strict 3D pipeline integrity: **117/117** PASS;
- `tools/test_mod.py --lua`: **191/191**, 0 failed, 0 skipped;
- MAX no-quality-loss contract: **5/5** PASS;
- aggressive compatibility: **HIGH 0**, MED 0;
- maintained release runner reached **ALL GATES PASSED** for its primary 80-tool summary and completed with the final marker **"all ok — safe baseline for next revision"**.

The retained stress wall also completed without failures, including the exhaustive weather catalogue, celestial stress, wind stress, BuildingLight stress, night scheduler, Weather-OFF cross-module contract, tornado safety, NPC lightning, rainbow, wind walking, procedural precipitation, fog ownership, sand pitch invariance, celestial projection/occlusion, all 25 approved constellation subjects, water ownership, synoptic transitions and mesoscale weather.

## Quality / gameplay preservation

8.1.51 intentionally does **not** reduce or remove:

- particle ceilings or weather intensity ranges;
- cloud bank density/height capability;
- world-front scale or handoff overlap;
- draw/effect distance settings;
- sun, moon, stars, planets, 25 constellations, aurora or celestial events;
- water, waves, tides, ripples, ice, SnowPack or Surf presentation;
- tornado, lightning, NPC lightning, wind or environmental interactions;
- battle/weather/audio/encounter/season/day-night behavior;
- player settings or native gameplay-speed authority.

## Release boundary

Absolute FPS, 1%-low, total driver VRAM, and physical-GPU timing are not claimed from this container. The measured performance claim is the isolated CPU-side removal of the remote-front mesh/hash preparation and per-frame hydrometeor vertex/index upload workload on supported instancing hosts. Unsupported hosts retain the exact visual fallback behavior.

The frozen ZIP hash, archive integrity, and fresh-extraction qualification are recorded externally in `weather_fx-core-8.1.51-validation.txt` and its SHA-256 sidecar after package freeze.
