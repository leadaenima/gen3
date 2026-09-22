# Weather FX 8.1.52 — Independent World-Space Storm Fronts / Physical Audio & Cloud Continuity

Built directly from exact Weather FX 8.1.51.

## What changed

- **Storm fronts no longer chase the player.** A front samples the player's world position once when spawned to choose its initial heading, then its target, heading and translation speed remain entity-owned state for the rest of its life. Later player movement cannot retarget or steer it.
- **Camera rotation cannot move weather simulation.** `HostAdapter.worldPosition()` now prefers the authoritative Scene player position (and voxel player fallback) before the legacy camera-focus fallback.
- **Smooth front translation.** `DistantWeather`'s bounded descriptor pass updates every rendered simulation frame instead of approximately every 0.18 seconds, eliminating visible stair-step front motion without increasing heavy cloud/particle simulation cadence.
- **Physical rain audio distance.** A rain-bearing front owns the rain bed by distance to its actual precipitation footprint. Spatial gain is 1.0 at the edge and throughout the footprint, then falls smoothly over 2,400 world units only after exit.
- **No post-exit audio snap-back.** The front remains the rain-bed authority through a zero-gain tail, so WeatherState's slower local channel decay cannot briefly restore full rain audio after the physical storm has moved away.
- **World-anchored front clouds.** Remote cloud banks are anchored to the front entity's physical leading edge, not to the point on the ellipse nearest the current player.
- **No lifecycle topology jumps.** Front clouds keep a fixed two-row descriptor topology; individual cloud masses fade in and part with deterministic continuous thresholds rather than being destroyed/recreated when stage labels change.
- **No teleport-filled local storm deck.** Finite-front cloud coverage drives the persistent cloud lattice's gate/soft-gate continuously. Clouds establish across the sky progressively and part progressively as the front moves through. Manual/config-selected weather keeps its authored immediate behavior.
- **No upward remote rain.** Both the instanced and CPU distant precipitation paths now use a monotonic Weather FX front clock. Rain remains `frontTop - travel` in world Y, so the fall phase cannot reverse because of host/camera animation time.
- **Continuous precipitation maturity.** Remote rain/snow shaft strength is a smooth function of normalized front life instead of stepping at formation/growth/mature/weakening labels.
- **Indoor weather stays audible.** Building occlusion can reduce the distance-adjusted weather bed by at most 60%, so at least 40% of the outdoor level remains. The indoor low-pass has the same retained-energy floor; WEATHER SFX OFF is still the only intentional full mute. Legacy QUIET/MUTED values are clamped into the new audible range.
- **Cycle weather is world-persistent across map changes.** Map entry no longer rerolls CYCLE or destroys live storm entities; the cycle timer advances by elapsed weather time rather than map transitions.
- **Fronts and CYCLE are mutually exclusive authorities.** With WEATHER FRONTS ON, physical fronts own automatic world weather and the CYCLE timer is suspended. Turn fronts OFF and CYCLE resumes from its preserved timer.
- **Named weather disables fronts.** Choosing a specific WEATHER from the menu immediately turns WEATHER FRONTS OFF and keeps that manual weather authoritative; fronts cannot silently steal control back while the named weather remains selected.

## Preserved from 8.1.51

- exact 9,000 MAX remote-front particle ceiling;
- hardware-instanced zero-CPU-hydrometeor-staging path on supported hosts;
- exact CPU fallback on unsupported/failed instancing;
- 62% remote/local precipitation overlap;
- all 68 player settings and MAX quality ceilings;
- Weather FX water, celestial, battle, seasonal, tornado, gameplay and compatibility systems not involved in this repair.

## New regression coverage

`front_entity_realism_8152_test.lua` proves camera independence, one-time player targeting, fixed heading/speed, linear world translation and persistence. `front_audio_motion_cloud_8152_test.lua` proves full in-front rain gain, post-exit distance attenuation, local-channel override prevention, world-anchored bank position, monotonic front time and lifecycle continuity. `weather_authority_8152_test.lua` proves named-weather/front mutual exclusion, persisted FRONT=OFF behavior, CYCLE suspension under front authority, map-change immunity, indoor timer freezing, and clean CYCLE resume after fronts are disabled. `test_8152_front_realism.py` statically locks the integration contracts.
