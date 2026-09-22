# Weather FX 8.2.7 Final Audit

## Scope

8.2.7 is built directly from the canonical preserved Weather FX 8.2.6 baseline. It is a corrective compatibility and visual-reliability release driven by extended real Gen1Recomp 0.2.53 + Battle Art Voxel Fork 1.10.4 framebuffer qualification rather than static inspection alone.

## Defects found by real 3D qualification

1. `GustFront` and `WorldInteractionPrecip` were shipped Weather FX 3D helpers but were not registered in the private voxel-atmosphere namespace. Battle Art 1.10.4 therefore attempted to resolve absent host/root modules before Weather FX could use its own implementations.
2. Speculative optional host-module lookups used Weather FX protected-call telemetry, so an expected missing optional host helper could be reported as a Weather FX failure.
3. The character-reflection puddle subpass assumed the older `puddleMask` host seam. Battle Art 1.10.4 does not expose it, causing a protected-call failure during wet 3D frames even though precipitation itself remained live.
4. Procedural snow declared and uploaded a `fieldIntensity` GLSL uniform that the shader never read. Real GLSL compilation optimized the dead uniform away; the failed `Shader:send` was then interpreted as a procedural-backend failure, dropping SNOW_LIGHT/BLIZZARD/THUNDERSNOW to the sparse CPU compatibility field.

## Repairs

- Registers Weather FX-owned `GustFront` and `WorldInteractionPrecip` in the private 3D namespace.
- Pins Weather FX-owned `Battle`, `SnowSurfacePaint`, `WeatherWorldInteraction`, and `RaveMusic` to Weather FX before optional host lookup.
- Uses ordinary protected probes for speculative optional host-module discovery so expected misses do not pollute Weather FX error telemetry.
- Feature-detects the optional puddle-mask reflection seam and skips only that cosmetic character-reflection subpass when absent.
- Removes the dead procedural-snow `fieldIntensity` declaration/upload; authored strength remains represented by the live `fieldFallScale` path.
- Uniform-upload diagnostics now identify the exact failed uniform name.

## Fresh real-renderer visual qualification

The final repaired source candidate was run through real Gen1Recomp/LÖVE with the real Battle Art Voxel Fork 1.10.4 renderer using Gen1Recomp's official ROM-free fixture dataset.

- 30/30 Weather FX catalogue entries rendered through the 3D host, including AUTO-only MIST.
- Every weather remained active for 30 simulated gameplay seconds at MAX Weather FX quality.
- 60/60 sustained 3D framebuffers were written (two per weather).
- 30/30 weather cases included real player movement.
- RAIN_HEAVY, BLIZZARD, SANDSTORM and RAVE each survived route -> town -> route 3D map transitions.
- Final long-dwell result: `failures=0`, voxel renderer still live.
- Repaired SNOW_LIGHT, BLIZZARD and THUNDERSNOW remain visibly populated after sustained dwell.
- Consecutive repaired BLIZZARD frames differ materially, demonstrating ongoing animated snow rather than a static overlay.
- Production-path diagnostics prove MAX BLIZZARD remains on the native `love_InstanceID` procedural backend with 800,000 logical flakes and bounded CPU interaction probes.

The 2D fixture qualification covers all 30 catalogue entries, all 80 player-facing setting rows / 357 declared choices, map transition and pause-menu weather. A separate state-based battle visual driver reached the real battle state, seeded battle weather `RAINY`, reached the command menu, and visually demonstrated Weather FX FULL -> OFF -> FULL while remaining in the same battle.

## Deterministic source qualification

- 8.2.7 private 3D namespace regression: **14/14 PASS**.
- Battle Art wet-compatibility regression: **5/5 PASS**.
- Procedural-snow optimized-uniform regression: **7/7 PASS**.
- Maintained developer sweep: **127/127 programs PASS**, RC=0.

## Exact-package replay

The versioned candidate ZIP was extracted into a clean directory and replayed through the release wall:

- Source/package content identity: **946/946 byte-identical**.
- Production runtime Lua compile: **129/129 PASS**.
- Revision gate: **80/80 PASS**.
- `test_mod.py --lua`: **198 passed, 0 failed, 0 skipped**.
- Feature integrity audit: **511/511 PASS**.
- Private 3D namespace: **14/14 PASS**.
- Battle Art wet compatibility: **5/5 PASS**.
- Procedural snow uniform regression: **7/7 PASS**.
- Maintained developer sweep: **127/127 programs PASS, RC=0**.

The final archive is rebuilt with this audit/qualification text embedded and replayed once more; its exact SHA-256 and archive-integrity results are published in the external validation record.

## Provenance and truth boundary

The canonical 8.2.6 Library ZIP and its Library checksum sidecar were rematerialized before freeze; the local 8.2.6 input is byte-identical to that canonical package. The official Gen1Recomp fixture is deliberately ROM-free and is not Pokemon Yellow. No fresh Pokemon Yellow 8.2.7 playthrough/framebuffer claim is made because the previously user-provided commercial ROM/generated cache is not available in the current workspace.

The fixture qualification is nevertheless a real Gen1Recomp/LÖVE + Battle Art production renderer execution: it validates Weather FX integration, world-space 3D rendering, weather animation, movement, map transitions, settings and battle presentation without substituting an offline/mock weather renderer.
