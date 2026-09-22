# Weather FX 8.2.7 — Battle Art 3D Compatibility + Procedural Snow Recovery

Built directly from exact Weather FX 8.2.6 after an extended real Gen1Recomp 0.2.53 + Battle Art Voxel Fork 1.10.4 framebuffer qualification exposed 3D integration defects that static/unit qualification did not reveal.

## Repaired Battle Art 1.10.4 integration

- `GustFront` now resolves to Weather FX `lib/voxel_atmos/GustFront.lua`.
- `WorldInteractionPrecip` now resolves to Weather FX `lib/voxel_atmos/WorldInteractionPrecip.lua`.
- Weather FX-owned `Battle`, `SnowSurfacePaint`, `WeatherWorldInteraction`, and `RaveMusic` APIs are pinned to the Weather FX root namespace before optional host lookup.
- Optional host-module discovery uses non-telemetry protected probes, so an expected missing optional host module no longer appears as a Weather FX protected-call failure.
- Puddle-masked character reflections now feature-detect the host `puddleMask` seam. Battle Art 1.10.4 does not expose it, so only that optional cosmetic reflection subpass is skipped; precipitation, puddles, fog, rays, lightning, water and the rest of the atmosphere continue normally.

## Repaired real 3D snow disappearance

The long-duration Battle Art framebuffer pass exposed that SNOW_LIGHT, BLIZZARD and THUNDERSNOW could fall onto the sparse CPU compatibility field even though the modern procedural GPU path was otherwise supported.

Root cause: the procedural snow GLSL declared and uploaded `fieldIntensity` but never read it. A real GLSL compiler correctly optimized that dead uniform away. Weather FX then treated the failed `Shader:send("fieldIntensity")` as a procedural-backend failure and abandoned the full GPU snow field.

8.2.7 removes that dead declaration/upload. Authored intensity is already incorporated into the live `fieldFallScale` uniform, so weather strength and density are not reduced. Uniform-failure diagnostics now include the exact uniform name.

Fresh production-path diagnostics after the repair prove MAX BLIZZARD owns the native `love_InstanceID` procedural backend with its full 800,000 logical flakes, `fullVisual=true`, `proven=true`, `failed=false`, while retaining only the bounded CPU interaction probe.

## Fresh visual qualification

Using the real Gen1Recomp/LÖVE renderer and real Battle Art Voxel Fork 1.10.4 with Gen1Recomp's official ROM-free fixture world:

- 30/30 weather catalogue entries rendered in 3D, including AUTO-only MIST.
- Every weather was then held for 30 simulated gameplay seconds at MAX Weather FX quality, with real player movement during every case: 30/30 movement checks, 60/60 sustained weather framebuffers, 0 Weather FX failures.
- RAIN_HEAVY, BLIZZARD, SANDSTORM and RAVE each survived route -> town -> route 3D map-transition stress.
- Repaired SNOW_LIGHT, BLIZZARD and THUNDERSNOW remain visibly populated after sustained dwell; consecutive BLIZZARD frames are visibly different/animated.
- RAVE's 3D lasers, rain, hail, sand/dust/fog families and other representative 3D effects were visually inspected in direct LÖVE framebuffer captures.
- Fresh 2D fixture qualification remains clean across all 30 weather types, all 80 player-facing settings / 357 declared choices, map transitions, pause weather, and in-battle Weather FX FULL -> OFF -> FULL A/B proof.

The fixture is intentionally not Pokémon Yellow. A fresh Pokémon Yellow 8.2.7 gameplay qualification is not claimed because the previously user-provided commercial ROM/generated cache is not present in the current workspace.

No authored weather density, rendering distance, quality ceiling, cloud population, celestial population, water behavior, snow density multiplier, or gameplay authority is reduced or transferred. Weather FX 8.2.6 remains preserved unchanged as the audit negative control.
