# Weather FX + Voxel Realism Benchmark

Weather FX Core 4.35.24 includes a deterministic in-game benchmark intended for real hardware comparisons between Weather FX revisions and Weather FX + Voxel Realism setting combinations.

## Run it

Open the developer console and use:

- `weather benchmark quick` — about 30 seconds; CLEAR, GALE, BLIZZARD, PSYSTORM.
- `weather benchmark full` — about 2 minutes; recommended hardware/spec test.
- `weather benchmark status` — current phase and time remaining.
- `weather benchmark stop` — stop immediately and restore pre-test weather/time.
- `weather benchmark last` — concise result from the most recent run.

Detailed per-phase results are written to the mod log with the prefix `WXBENCH`.

## Fair LOW vs MAX testing

1. Use the same game build, Weather FX build and Voxel Realism build.
2. Stand in the same outdoor location with buildings, vegetation and several NPCs visible. A town edge or dense route is preferable to an empty interior.
3. Use the same resolution, camera mode, render distance and window/fullscreen mode.
4. Set **both mods** to the preset being measured before starting the benchmark. The benchmark does not change quality settings itself.
5. Avoid opening menus, moving the window or changing camera/settings during the run.
6. Run `weather benchmark full` at least three times after the first warm run. Compare medians rather than one unusually good/bad run.

For a MAX-settings hardware requirement, use maximum Weather FX and Voxel Realism settings. For a LOW requirement, select LOW/POTATO-equivalent display settings in both mods while leaving all gameplay/weather systems enabled.

## Full benchmark phases

1. **CLEAR BASELINE** — base voxel world and normal Weather FX overhead.
2. **HEAVY RAIN** — world precipitation, wet effects, splash/puddle pressure and rain audio.
3. **GALE / LEAVES** — WindEngine, heavy wind/rain, 3D leaf collision and pile activity.
4. **BLIZZARD / SNOW** — large 3D snow field, flake collision, SnowPack deposition and footprint state.
5. **SANDSTORM** — grain/debris pressure and atmospheric obscuration.
6. **FOG / FILL** — fog/mist transparency/fill-rate pressure.
7. **PSYCHIC STORM** — multi-bolt lightning, per-bolt distance thunder and NPC-lightning targeting.
8. **NIGHT / CELESTIAL** — stars, planets, sun/moon/celestial and shadow-related night presentation.

Each phase has an unmeasured warm-up window before samples are collected so weather switches, shader setup and pool activation do not unfairly dominate the phase.

## Metrics

The benchmark measures the **whole game frame**, which is what matters for combined-mod hardware requirements:

- average FPS;
- 1% low FPS;
- 0.1% low FPS;
- p95 and p99 frame time;
- frames above 33 ms, 50 ms and 100 ms.

It also records Weather FX-specific timing/telemetry:

- Weather FX update time;
- Weather FX voxel-atmosphere draw time;
- Weather FX final-present time;
- Lua memory average/peak;
- draw-call average/peak;
- texture-memory usage reported by LÖVE (a GPU-memory proxy, not a guaranteed total VRAM reading);
- live rain, snow and grain/debris peaks;
- SnowPack active-cell peak;
- footprint peak.

LÖVE does not expose portable GPU timestamp queries to sandboxed mods, so the benchmark does **not** claim a true GPU execution-time measurement. Whole-frame time plus draw-call/texture-memory telemetry is used instead.

## Ratings

The summary intentionally uses the **worst phase 1% low**, not just average FPS:

- `EXCELLENT-120` — average >=120 FPS and worst phase 1% low >=115 FPS.
- `EXCELLENT-60` — average >=60 FPS and worst phase 1% low >=58 FPS.
- `GOOD-60` — average >=58 FPS and worst phase 1% low >=50 FPS.
- `PLAYABLE` — average >=50 FPS and worst phase 1% low >=40 FPS.
- `MARGINAL` — worst phase 1% low >=28 FPS.
- `TOO-SLOW` — below that threshold.

For published recommended specs, target at least `EXCELLENT-60`; ideally require worst-phase 1% lows close to 60 FPS rather than accepting a high average with heavy storm stutter.

## Safety / state restoration

The benchmark changes weather/time only in memory. It suppresses WeatherState persistence for the duration of the run and restores the original weather ID, channel values, transition state and time pin when it completes or is stopped. GALE's tornado warp action is also suppressed during a benchmark so the player cannot be moved to another map in the middle of a run.

If the voxel 3D bridge is inactive or the benchmark begins indoors, the HUD and start message warn that the run is not a valid Weather FX + Voxel Realism combined result.
