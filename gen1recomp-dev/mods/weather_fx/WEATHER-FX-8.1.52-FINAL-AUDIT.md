# Weather FX 8.1.52 — Final Release Audit

## Release identity

Weather FX **8.1.52**, "Independent World-Space Storm Fronts / Persistent Weather Authority", is built directly from the exact preserved Weather FX 8.1.51 package (`81914ea8ffe26131019edcb7e3fa2068554e369645df3178e497010e55e713bd`).

## Player-reported repairs

- Storm fronts are persistent world-space entities. They sample the player's position once at spawn to establish a trajectory and never home toward later player movement.
- Camera focus/look direction is no longer accepted ahead of the authoritative player world position, so turning the camera cannot drag storm fronts or cloud banks.
- The lightweight distant-front descriptor refreshes every simulation frame, removing the old ~0.18 s visible movement stepping without raising the heavy cloud/particle cadence.
- Front cloud topology is stable through the lifecycle. Cloud masses progressively establish and part instead of teleport-filling the sky at stage boundaries.
- Remote rain/snow animation uses a monotonic Weather FX front clock; rain travel remains downward in world Y and cannot reverse because of host/camera time.
- Rain-front audio is 100% of its authored bed gain throughout the precipitation footprint and only begins distance attenuation after the player exits the storm.
- Receding-front audio remains authoritative through its distance tail so the local eased rain channel cannot snap the sound off/on at the footprint edge.
- Indoor automatic weather attenuation is capped at 60%: at least 40% of the distance-adjusted outside weather bed remains audible. Indoor filtering also retains at least 40% high-frequency energy. WEATHER SFX OFF remains a true mute.
- CYCLE weather is persistent across map changes and advances only on its timer. Map transitions do not reroll it.
- Live storm entities persist across map-space epoch changes; changing maps moves the observer, not the storm.
- WEATHER FRONTS and CYCLE are mutually exclusive automatic authorities. With fronts enabled, fronts own world weather and the CYCLE timer is suspended. With fronts disabled, CYCLE resumes from its preserved timer.
- Selecting a named WEATHER immediately disables WEATHER FRONTS and keeps the player's selected weather authoritative. Fronts cannot be re-enabled while that named weather remains selected; return WEATHER to AUTO/CYCLE first.

## Runtime delta versus exact 8.1.51

Exactly these existing runtime files differ from the 8.1.51 runtime freeze:

- `config.lua`
- `lib/Audio.lua`
- `lib/Config.lua`
- `lib/DistantWeather.lua`
- `lib/DramalessAtmos.lua`
- `lib/EngineRuntime.lua`
- `lib/HostAdapter.lua`
- `lib/Settings.lua`
- `lib/StormCells.lua`
- `lib/WeatherState.lua`
- `lib/WeatherWorldSpace.lua`
- `lib/voxel_atmos/CinematicAtmos.lua`

The 8.1.51 zero-upload front-instancing module (`lib/DistantFrontPrecip.lua`), `lib/Quality.lua`, `lib/voxel_atmos/WorldPrecip.lua`, and `lib/voxel_atmos/ConnectedWater3D.lua` remain byte-identical to 8.1.51.

## Performance preservation

The authored MAX remote-front ceiling remains **9,000 particles** and the remote/local precipitation handoff remains **62%**. Supported hosts retain the 8.1.51 hardware-instanced front precipitation path with no CPU hydrometeor mesh staging; unsupported hosts retain the exact CPU fallback. The new frame-live work is only the bounded front descriptor observer, not the heavy particle/cloud simulation.

## Dedicated 8.1.52 regression results

- `front_entity_realism_8152_test.lua`: **9/9 PASS** — camera independence, spawn-only targeting, fixed heading/speed, linear translation, map-epoch persistence, save/reload trajectory preservation.
- `front_audio_motion_cloud_8152_test.lua`: **15/15 PASS** — full in-front rain gain, post-exit distance falloff, zero-gain tail ownership, world-anchored bank, monotonic precipitation clock, lifecycle continuity, 40% indoor gain/filter floors.
- `weather_authority_8152_test.lua`: **10/10 PASS** — named-weather/front mutual exclusion, persisted dependent FRONT=OFF, CYCLE suspension under front authority, map-change immunity, indoor CYCLE freeze, clean CYCLE resume after fronts are disabled.
- `test_8152_front_realism.py`: **13/13 PASS**.
- `test_8152_package_surface.py`: **30/30 PASS** before final-audit insertion; re-run after freeze is required by packaging.
- `test_8152_performance_contract.py`: **8/8 PASS**.
- `test_8152_runtime_delta.py`: PASS, exactly 12 intended runtime files changed.
- `test_8152_runtime_freeze.py`: **162/162 PASS**.

## Full inherited regression wall

The clean maintained runner was executed with Python bytecode generation disabled after removing transient cache files:

`python tools/run_all.py --lua`

Result: **exit code 0**. Final marker: **`all ok — safe baseline for next revision`**.

This includes the inherited 8.1.51 instancing/MAX-settings gates, 8.1.50 front precipitation continuity, all player settings/runtime checks, storm-front/water/VOID ownership, celestial/night-sky/aurora, battle, lightning, wind, world precipitation, voxel-host compatibility, strict 3D presentation, safety/hardening, performance invariants and package/revision gates.
