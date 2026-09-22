# Weather FX 8.2.5 Final Audit

## Scope

Built directly from exact Weather FX 8.2.4. Per user instruction, this release changes only logical/procedural 3D snow population for the named player-facing weather types.

- SNOW (`SNOW_LIGHT`; legacy `SNOW` alias): exactly 2x its 8.2.4 3D snow population.
- TSNOW (`THUNDERSNOW`): exactly 2x its 8.2.4 3D snow population.
- DRAGON (`DRAGONSTORM`): exactly 2x its 8.2.4 3D snow population.
- BLIZZARD: exactly 4x its 8.2.4 3D snow population.

No other weather is multiplied. WHITEOUT, SLEET, FROST/ICE variants and other weather retain their existing density/behavior.

## Performance-safety preservation

The 8.2.4 bounded CPU fallback budgets are intentionally unchanged. The requested multiplier applies to the logical/procedural GPU visual population only. Snow accumulation behavior, screen-space point/detail LOD, smooth per-render-frame motion, live render distance, no-emitter continuity, clouds, RAVE, celestial, battle, rain and all unrelated systems remain unchanged.

## Executed verification

- Dedicated 8.2.5 density regression: 9/9 PASS.
- Exact 8.2.4 negative control: 7/9 new checks FAIL as required; unchanged WHITEOUT/SLEET controls PASS.
- Five-tier executable density matrix: all requested ratios exact (2.00x / 4.00x), controls 1.00x.
- Maintained developer sweep: 123/123 programs PASS.
- test_mod.py --lua: 198 passed, 0 failed, 0 skipped.
- Revision gate: 80/80 PASS.
- Runtime Lua compile: 129/129 PASS.
- Runtime Lua delta vs exact 8.2.4: exactly one changed file, `lib/voxel_atmos/WorldPrecip.lua`.

## Truth boundary

No fresh interactive Gen1Recomp FPS/framebuffer capture on the user's exact phone/desktop GPU is available in this environment. This release verifies the requested population ratios and preservation contracts, not a fabricated device FPS result.
