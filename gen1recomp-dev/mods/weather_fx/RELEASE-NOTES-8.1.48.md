# Weather FX 8.1.48 — EngineRuntime Compile Repair

## Player-reported failure

Weather FX 8.1.47 could fail at Mod Manager load with `lib/EngineRuntime.lua did not compile` and a Lua parser error near line 10.

## Root cause

The 8.1.47 pruning edit added a documentation bullet to the header of `lib/EngineRuntime.lua`, but that one line accidentally lost the Lua `--` comment prefix. It was therefore parsed as Lua code even though it was only intended to be a comment.

## Repair

8.1.48 restores the missing comment prefix. The exact runtime delta from 8.1.47 is only `lib/EngineRuntime.lua`, and inside that file the behavioral code is unchanged; only the malformed comment line is repaired.

## Preservation

All 8.1.47 zero-quality-loss pruning remains intact: the four advisory passes stay on-demand, the volumetric descriptor remains virtualized with exact renderer-facing output, flat-world footprint caching remains active, and manual QUALITY still avoids AUTO-only bookkeeping. No graphics, particles, textures, water/reflections, clouds/fronts, celestial detail, constellation behavior, aurora, snow/leaves, audio, settings or gameplay behavior is reduced or otherwise changed.

## Qualification boundary

The release is syntax-compiled across every shipped Lua file and reruns the 8.1.47 pruning/visual/gameplay regression gates. Live framebuffer appearance still requires the game, but this repair targets a deterministic pre-load compiler failure rather than a visual effect.
