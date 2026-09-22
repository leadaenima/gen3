# Weather FX 8.1.32 — Mega Performance Audit

8.1.32 is built directly from the exact 8.1.31 Real Rolling Water / Native Water Handoff baseline. This release is intentionally narrow: remove measurable CPU/GC waste without reducing authored quality or changing gameplay semantics.

## Proven steady-state waste removed

A controlled four-body water benchmark on the frozen 8.1.31 source executed 20,000 steady `ConnectedWater3D.prepare()` calls with GC stopped. 8.1.31 produced approximately 63,603 KiB of transient Lua allocation, 80,000 protected module lookups, 20,000 `ConnectedWater.sample()` diagnostics snapshots, and 80,000 translation-matrix constructions. The same benchmark after the 8.1.32 changes produced approximately 27,511 KiB, four initial module lookups, zero diagnostics snapshots, and four initial liquid translation matrices. That is about a 56.7% reduction in measured transient allocation for this controlled water-prepare path and about a 15% reduction in the microbenchmark CPU time on this container. These are microbenchmark deltas, not a claim of a 15% whole-game FPS increase.

`ConnectedWater.update()` also stops protected-resolving WindEngine, CelestialSim, TimeOfDay and Microclimate every tick. A 20,000-update microbenchmark reduced dependency resolutions from 80,000 to four while preserving liquid-water physics; Settings is likewise cached after first use.

## Safety boundaries

- Successful module handles are reused only inside the same Weather FX instance. Missing modules remain retryable. `ConnectedWater3D.invalidate()` clears cached host handles so WATER STYLE handoff/hot reload re-resolves safely.
- Reflective translation-matrix reuse is restricted to the exact structured Voxel Realism relief-water contract already required for centered crest/trough behavior. Unknown/older Water APIs continue through the conservative host `Mat4.translate()` path.
- Voxel Realism `Water.draw()` sends the model matrix every draw, so updating the reused reflective matrix does not rely on Voxel3D's separate model-identity cache. Progressive skim ice continues to use a fresh host matrix so its scene-shader tide transform is always resent.

## No quality reductions

8.1.32 does not reduce MAX or any manual tier. It does not lower rain/snow/blizzard/hail/sand/debris/ash populations, the 5,120 ordinary-star catalogue, planet/constellation content, cloud field radius, StormCell count, water body count, wave peak-to-trough relief, 48-ripple cap, ice texture quality, SnowPack coverage, draw distance, shadow quality, or any setting range.

## Settings and gameplay audit scope

The in-game schema remains 62 settings. The live Gen1Recomp ManagerState sweep writes every selectable value through the real mod option persistence + `mod.options_changed` path (349 value applications total) and restores defaults. Static/executable setting gates additionally verify defaults, value domains, runtime consumers, menu grouping, intensity controls, quality behavior, time-of-day, audio, storms/tornado controls, battle controls and WATER STYLE semantics.

## Host/performance interpretation

Real-host qualification uses Gen1Recomp 0.2.53 / LÖVE 11.5 + Pokémon Yellow + the newest complete Voxel Realism package available for this audit (1.9.1). The container renders through software OpenGL/llvmpipe, so absolute FPS is **not** presented as a player-hardware benchmark. Relative hot-path timing, allocation counts, runtime errors, state transitions and setting behavior are valid audit evidence. Known Voxel 1.9.1 warnings about the bundled Stadium importer namespace, `src.render.GBCFX`, optional host probes and its unavailable terrain-cache backend remain host-side issues and are not reclassified as Weather FX regressions.

## Final live qualification

The frozen 8.1.32 candidate was installed into the preserved Gen1Recomp 0.2.53 / LÖVE 11.5 + Pokémon Yellow + Voxel Realism 1.9.1 stack and exercised in the actual voxel renderer.

- **29/29 weather types rendered** in five bounded live batches; each active WeatherState id matched the requested weather and all 29 framebuffer captures were written. The heavy families reached their authored live populations during the sweep, including SNOW_LIGHT 100,000, BLIZZARD 200,000, HAIL 45,000, SANDSTORM/DUSTSTORM 43,200, STRONG_WINDS/SWARM 3,600 debris, and ASHFALL 10,800. The very short RAIN_LIGHT capture occurred before its particle field had ramped and therefore reported zero rain at that exact early diagnostic; later heavy-rain/storm scenarios independently proved the live rain pipeline.
- **62/62 settings / 349/349 selectable value applications** completed through Gen1Recomp's real ManagerState persistence + `mod.options_changed` path with zero failures.
- **Connected water handoff** remained live: four bodies / 1,583 cells; WEATHER FX -> ORIGINAL disabled the Weather FX renderer; ORIGINAL -> WEATHER FX re-enabled it. Surf presentation bob changed with wave phase while gameplay X/Y stayed unchanged.
- **Player path**: real directional input moved the player from Pallet Town (8,14) to (8,13), an interior map was loaded and accepted directional input/collision, and an actual wild Pidgey level-5 battle was pushed through Gen1Recomp's normal BattleTransition. The BattleState became visible and rendered the real battle composition with Weather FX active.
- Candidate-specific real-dt software-renderer stress runs kept the full heavy weather workloads active. Because this container uses llvmpipe software OpenGL, absolute FPS is not used as a player-hardware performance claim; the controlled water microbenchmark above remains the quantitative optimization proof.

No new Weather FX runtime exception was observed in these live qualifications. The known Voxel Realism 1.9.1 Stadium importer/GBCFX/optional-probe/cache-backend warnings remain inherited host-side warnings.
