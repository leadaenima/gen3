# Weather FX 8.1.88 — Final Qualification

Built directly from exact Weather FX 8.1.87.

## Qualified additions

- Stable roof-edge runoff and post-rain eave drips from exact live voxel support.
- Delayed canopy dripping with true permeable-canopy pass-through preserved.
- Material-aware precipitation impacts for water, vegetation, ice, hard surfaces, and soil.
- One bounded travelling gust front in canonical world space, independent of camera orientation.
- Restrained post-rain enhancement of the existing cloud-aware solar shaft renderer.
- Environment SDK v5 vegetation/weather-load interoperability without companion geometry or NPC ownership.
- Final-frame classic 2D weather ownership on voxel hosts, preventing intermediate world canvases from swallowing `2D OVERLAY`.
- OPTIONS/Mod Manager weather authority synchronization that no longer requires visiting Mod Manager to activate a change.

## Qualification results

- Focused 8.1.88 regression tests: 36/36 PASS.
- Maintained developer sweep: 92/92 programs PASS when run in bounded segments (83 Lua, 8 Python, plus aggregate validator).
- `test_mod.py --lua`: 191 passed / 0 failed / 0 skipped.
- Shipped runtime Lua parse: 128/128 PASS.
- LuaJIT guard: WorldPrecip.update estimated direct upvalues 51 / ship ceiling 55 / hard ceiling 60.
- Existing 8.1.87 rain continuity, rendered-world rain, RAVE laser, and battle-weather persistence regressions remain PASS.
- Exact 8.1.87 negative control: 8/8 expected-absence checks PASS.
- Pre-fix 8.1.88 2D/options negative control: 0/4 PASS, while the fixed build is 4/4 PASS.

## Scope limits

No fresh live-game framebuffer/device session was available. The new visual effects are qualified by executable logic, render contracts, source inspection, prior host regressions, and package checks; this file does not claim a manual in-game visual playtest.
