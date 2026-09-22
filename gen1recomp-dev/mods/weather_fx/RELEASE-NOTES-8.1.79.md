# Weather FX 8.1.79 — Zero-Quality-Loss Runtime Cleanup

## Goal

8.1.79 is a performance/cleanup release built directly from exact 8.1.78. It reduces Lua hot-path allocation and redundant CPU work without lowering visual quality, weather reach, particle limits, cloud geometry, shadow quality, constellation geometry/brightness, settings, or authored weather behavior.

## Runtime changes

- **RenderGraph** caches interval type/value and pass-stat references at registration instead of re-resolving them on every execute pass.
- **Procedural rain/hail/sand/ash** reuses module-owned uniform vectors and sends uniforms directly instead of allocating a temporary uniform descriptor table each draw.
- **Procedural snow** applies the same persistent uniform/vector scratch strategy.
- **WorldPrecip** reuses procedural eye/wind/tint option vectors for live rain, snow, hail, sand and ash draw/probe paths. Scratch is stored on the module table so the already-large LuaJIT closure remains under the shipping headroom limit.
- **SnowSurfacePaint** reuses radius lookup, shader-uniform and inverse-matrix scratch; the coverage raster is protected as one batch instead of wrapping every individual `setPixel` call in a protected call.
- **WeatherShadowMap** caches immutable clip-to-texture/fit vectors, evaluates the same eight fit corners without temporary arrays, and performs one exact light-space fit per shadow recast. Shadow resolution changes only recompute the resolution-dependent bias/slack scalar, because the clip/UV fit itself is resolution-independent.
- **Constellations** defers expansion of the 8,507 immutable traced star objects until STARS/BY_NAME/count/draw is actually requested. The exact source traces, positions, colors, 0.82 peak-luma normalization, point counts and rendering hierarchy are unchanged.
- **CloudField** caches frame-invariant climate scalars and the fixed active-cell count once per update instead of repeatedly converting the same values across all 49 cells.

## Preserved 8.1.78 contracts

When **WEATHER FRONTS = OFF**, the 8.1.78 absolute rendered-world rain grid is unchanged. At **3D WEATHER DISTANCE = 100%**, Weather FX still reaches the exact live voxel render distance; 75/50/25% reduce only Weather FX coverage. WEATHER FRONTS ON retains its regional/front-owned behavior.

The release also preserves the existing MAX/base particle budgets used by the current renderer, including rain 12,000, hail 45,000 and base snow 100,000 (with the existing blizzard multiplier path intact).

## Qualification

The new `tests/performance_cleanup_8179_test.lua` regression passes 25/25 on 8.1.79. The exact 8.1.78 negative control passes only 11/25 and fails the 14 checks specific to the new cleanup, proving the test distinguishes the release from its baseline.

Broad source gates are green: revision 80/80, performance invariants 66/66, 3D pipeline 117/117, feature integrity 505/505, LuaJIT headroom PASS, and `test_mod.py --lua` 191/191.

No fresh live-game framebuffer is claimed by this release environment; executable/package qualification is not represented as a substitute for final host visual confirmation.
