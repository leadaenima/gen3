# Weather FX 8.1.99 — BLIZZARD + 2D Weather Repair

Built directly from exact Weather FX 8.1.98.

## Fixes

- **BLIZZARD follower fountain:** the modern GLSL3 procedural snow path now derives flake identity from native `love_InstanceID`. A full 200,000-flake fixed field is one instanced draw instead of replaying the same 8,192-row seed window across many chunks. The compatibility attribute-seed backend remains available on older hosts.
- **2D sun/moon camera lock:** 2D celestial projection now prefers the voxel host's real live camera forward vector, then FirstPerson yaw/pitch or live horizontal heading, before falling back to eye/focus. This prevents a static player/world focus anchor from making the sun and moon appear stapled to the camera.
- **2D snow startup dump:** freshly allocated snow is phase-distributed across its normal visible fall lifetime. Recycled flakes still re-enter from above, so steady-state behavior is unchanged.
- **2D WEATHER LIGHTNING:** new `2D BOLTS / 3D BOLTS` setting. It applies only when WEATHER RENDERING is `2D OVERLAY`. `3D BOLTS` keeps 2D precipitation/fog/weather while waking only the depth-tested world-lightning pass on compatible voxel hosts. If that pass is unavailable or unhealthy, Weather FX falls back to the working 2D bolt. Normal 3D weather lightning is unchanged.

## Preserved behavior

8.1.98 RAVE cloud thickness/zenith coverage, snow walking continuity, snow ownership, authored precipitation caps, accumulation, water, tornadoes, battles, audio and gameplay rules are preserved. The default for the new lightning selector is **2D BOLTS**, matching existing 2D-weather behavior.

## Validation

- `snow_native_instance_id_8199_test.lua`: **12/12 PASS**.
- `weather_2d_repairs_8199_test.lua`: **14/14 PASS**.
- Maintained developer sweep: **115/115 programs PASS**.
- `test_mod.py --lua`: **195 passed, 0 failed, 0 skipped**.
- Exact-package qualification is recorded in the final validation artifacts.
