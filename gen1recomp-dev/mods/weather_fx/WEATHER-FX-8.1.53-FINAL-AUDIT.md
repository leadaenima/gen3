# Weather FX 8.1.53 — Final Release Audit

## Release identity

Weather FX **8.1.53**, **Spatial Cloud-Sun Terrain Lighting**, is built directly from the exact preserved Weather FX 8.1.52 baseline.

The behavioral runtime delta is deliberately limited to:

- `lib/CelestialEngine.lua`;
- `lib/voxel_atmos/CinematicAtmos.lua`;
- `lib/voxel_atmos/WorldCelestialLighting.lua`.

Every other file tracked by the 8.1.52 runtime freeze remains byte-identical.

## Root cause repaired

The visible cloud ray sampled at the player was being used for two different jobs. It correctly controlled local solar/lunar disc and deep-sky occlusion, but it also multiplied the shared `direct` world-light value and its inverse was published as if it were regional cloud coverage. A small opening directly over the player could therefore raise `sunLight`/`directLight` for the entire loaded voxel scene.

## 8.1.53 lighting model

- Player-local cloud transmission now controls **only** local celestial visibility: sun/moon disc transmission, deep-sky visibility and shaft occlusion.
- Shared world direct light is driven by **regional** cloud coverage rather than the single player ray.
- Regional coverage is reconstructed from a bounded **3×3 world-space sample footprint** using the exact visible cloud descriptors and solar shear.
- Terrain cloud occlusion remains spatial. `WorldCelestialLighting` now projects the same rotated four-lobe macro cloud body used by `CinematicAtmos` occlusion, so terrain under clouds remains shaded while actual gaps are the brighter regions.
- The pass remains bounded to **18 visible clouds × 4 lobes = 72 maximum terrain patches** in one streamed draw. No per-pixel cloud ray march, framebuffer shadow texture, large new buffer, or new resident simulation grid is introduced.

## Executable proof

`tests/cloud_sun_localization_8153_test.lua` proves:

- changing only the player-local cloud ray from fully open to nearly opaque does **not** change map-wide `sunLight` or `directLight`;
- that same local ray still strongly hides the solar disc;
- increasing regional cloud coverage materially reduces world sunlight;
- localized terrain cloud geometry is submitted as one bounded draw;
- the terrain mask remains at no more than four macro lobes per visible cloud.

Result: **10/10 passed**.

`tools/test_8153_cloud_sun_localization.py`: **6/6 passed**.

Additional 8.1.53 gates:

- runtime delta: exactly 3 intended runtime files changed;
- runtime freeze: **162/162**;
- package surface: **16/16**;
- performance preservation: **11/11**;
- inherited celestial engine: **49/49**;
- inherited render pipeline after final integration form: **352/352**.

## Full maintained regression coverage

The maintained `tools/run_all.py --lua` command list exceeds the execution window of a single container call because of its inherited stress suites. For release qualification, the unchanged command list was executed in five contiguous, non-overlapping runner segments (with boundary overlap only where useful), each finishing with **exit code 0**:

1. current 8.1.53 gates through 8.1.28 world-scale/snow tests — exit 0;
2. 8.1.27 through revision gate and 8.1.1 truth contract — exit 0;
3. 8.1.2 safety through LuaJIT/performance/weather stress — exit 0;
4. strict 3D pipeline through direct-sun/sunset optics — exit 0;
5. celestial LOD through the final mod/compatibility/audit tail — exit 0.

Together these segments cover every executable command in the maintained runner. No test is skipped from the runner list.

## Preserved contracts

8.1.53 preserves all 8.1.52 fixes: independent non-homing world-space fronts, frame-smooth front clouds, continuous formation/parting, downward remote rain, physical distance front audio, the indoor 40% retained weather-audio floor, map-persistent weather/front/cloud state, front-exclusive authority over CYCLE, and named-weather front disabling.

It also preserves 8.1.51's zero-upload distant-front instancing architecture, exact **9,000-particle MAX** remote-front ceiling, **62%** remote/local precipitation handoff, CPU fallback, all **68** player settings, water systems, celestial catalogue and authored quality ceilings.
