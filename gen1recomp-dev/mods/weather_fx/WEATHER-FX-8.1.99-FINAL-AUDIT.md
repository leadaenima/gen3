# Weather FX 8.1.99 Final Audit

## Scope

Built directly from exact Weather FX 8.1.98. This release addresses the remaining BLIZZARD player-following 3D snow fountain plus three 2D-weather issues: sun/moon camera locking, the first-start snow dump, and selectable 2D versus 3D lightning bolts while weather remains 2D.

## Runtime repairs

Seven shipped runtime Lua files change versus exact 8.1.98: `lib/ProceduralSnowField.lua`, `lib/Particles.lua`, `lib/Settings.lua`, `lib/Draw.lua`, `lib/NightSky.lua`, `lib/DramalessAtmos.lua`, and `lib/voxel_atmos/CinematicAtmos.lua`.

The procedural BLIZZARD renderer uses native `love_InstanceID` on capable GLSL3 hosts, eliminating repeated 8,192-instance seed windows while preserving the exact 200,000-flake MAX BLIZZARD population. Compatibility fallback remains intact.

Fresh 2D snow now starts distributed throughout normal flake lifetimes instead of placing every new flake in one narrow top strip. Recycled flakes still enter from above.

2D celestial projection now prefers explicit live camera orientation (`camera.forward`/`camera.look`, FirstPerson yaw/pitch, or `lookFlat`) before using eye/focus. This closes the host case where focus is a static player/world anchor rather than a look target.

A new **2D WEATHER LIGHTNING** selector defaults to **2D BOLTS** and can select **3D BOLTS** only for forced 2D overworld weather. The mixed path wakes world lightning without enabling 3D precipitation, fog, RAVE, puddles, rays, or other full-weather passes. If world lightning is not healthy, the classic 2D bolt remains the fail-open fallback.

## Validation

- Native BLIZZARD instance-ID regression: **12/12 PASS**.
- New combined 2D weather repair regression: **14/14 PASS**.
- 2D celestial world-lock regression: **3/3 PASS**.
- Celestial zenith projection: **40/40 PASS**.
- 2D weather style: **94/94 PASS**.
- World lightning: **493/493 PASS**.
- 2D NPC lightning: **15/15 PASS**.
- Settings runtime: **761/761 PASS**.
- Complete settings descriptions: **1945/1945 PASS**.
- Simultaneous maximum-settings profile: **10/10 PASS**.
- Settings/runtime audit: **280/280 PASS**.
- Maintained developer sweep: **115/115 programs PASS**.
- `test_mod.py --lua`: **195 passed, 0 failed, 0 skipped**.

## Truth boundary

These are deterministic code/runtime harness and package checks. This environment does not provide a fresh interactive Gen1Recomp framebuffer/player session on the user's exact GPU/driver, so the final real-device visual check remains decisive for the reported BLIZZARD fountain and 2D presentation behavior.
