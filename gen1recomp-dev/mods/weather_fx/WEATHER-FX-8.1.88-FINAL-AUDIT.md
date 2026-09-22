# Weather FX 8.1.88 — Final Audit

Built directly from exact Weather FX 8.1.87.

## Runtime delta

Exactly ten runtime Lua files differ from 8.1.87:

1. `lib/EngineRuntime.lua` — adds the lightweight per-frame weather-world interaction stage.
2. `lib/EnvironmentSDK.lua` — advances the public read-only environment API to v5 and exposes weather interaction state.
3. `lib/WeatherWorldInteraction.lua` — new retained-water, post-rain optics, vegetation-load, and world-space gust-front state authority.
4. `lib/voxel_atmos/CinematicAtmos.lua` — keeps the 3D atmosphere alive for residual interaction, applies bounded post-rain ray gain, and draws the world-space gust pass.
5. `lib/voxel_atmos/GustFront.lua` — new bounded depth-tested 3D gust-front renderer.
6. `lib/voxel_atmos/WorldInteractionPrecip.lua` — new bounded roof/eave/canopy secondary-precipitation and material-impact helper.
7. `lib/voxel_atmos/WorldPrecip.lua` — connects exact support hits to material-aware splashes and roof/canopy secondary precipitation while preserving canopy permeability.
8. `lib/Settings.lua` — preserves live option mirrors across schema re-registration and adds an always-running engine WEATHER-ladder reconciliation path.
9. `lib/SettingsMenu.lua` — mirrors custom OPTIONS submenu edits into the real core-game loader caches even when the UI passes a lightweight game facade.
10. `main.lua` — exposes the read-only `weatherWorldInteraction` snapshot, polls the WEATHER ladder from `render.hud`, and defers forced 2D weather to the final-frame compositor.

## 2D/options release-blocker repairs

- Forced `2D OVERLAY` no longer claims `worldPresent`; it renders in final `present()` so voxel-host intermediate world targets cannot swallow the classic overlay.
- Base OPTIONS WEATHER changes are reconciled from an always-running render seam and do not depend on the decorated row callback or on visiting Mod Manager.
- Option-schema re-registration preserves live runtime mirrors.
- The custom Weather FX OPTIONS submenu updates the real loader caches used by Mod Manager/mod option reads.

## Ownership and performance

No Terrarium weather scheduler, sky renderer, puddle engine, snow accumulation engine, water renderer, cloud engine, or NPC controller was copied into Weather FX. The new work is native to Weather FX's existing WindEngine, EnvironmentSurface, SnowPack, cloud-transmission, and environment SDK architecture.

Secondary drips are capped at 128; roof-edge resolution is budgeted to at most three searches per precipitation update; post-rain roof/tree source discovery is at most two exact-support samples per update; the gust front is 48 vertices while active. WeatherWorldInteraction itself is O(1).

## Regression evidence

- 8.1.88 focused tests: 36/36 PASS.
- Maintained developer sweep, executed in bounded segments: 92/92 programs PASS (83 Lua, 8 Python, plus aggregate validator).
- `test_mod.py --lua`: 191 passed, 0 failed, 0 skipped.
- Shipped runtime Lua syntax parse: 128/128 PASS.
- LuaJIT limit guard: WorldPrecip.update estimated 51 direct upvalues (ship ceiling 55; hard limit 60).
- Edit guard: PASS.
- Shader attribute/GLSL portability gate: PASS.
- Engine architecture static gate: 11/11 PASS.
- Environment Engine 3 static gate: 30/30 PASS.
- Exact 8.1.87 negative control: 8/8 expected-absence checks PASS.
- Pre-fix 8.1.88 2D/options negative control: 0/4 PASS (all four defects reproduced).
- The standalone package does not contain `tools/modkit.py`, so the AGENTS.md external modkit validate/gen2check/lint/pack commands were not runnable in this extracted build environment.
- `test_scope_hygiene.py` still reports the pre-existing `configModule` global in `WorldPrecip.lua`; exact 8.1.87 reports the same issue, so it is not an 8.1.88 regression. Making that helper local would consume main-chunk local budget in a file already constrained by Lua's 200-local limit, so this update leaves the baseline behavior unchanged.

No fresh live-game framebuffer/device session was captured; this audit does not claim manual visual validation.
