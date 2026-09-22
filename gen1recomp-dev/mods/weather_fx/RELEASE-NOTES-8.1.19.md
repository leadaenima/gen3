# Weather FX 8.1.19 — Weather-owned Shadow Engine

Weather FX 8.1.19 builds directly on 8.1.18 and replaces the compatible voxel host's shadow-map implementation in memory. No voxel-host files or saved host options are modified.

## What changed

- Weather FX owns the shadow texture, writer shader, projection, cache/recast policy and GPU lifecycle.
- Existing host caster submission remains the integration seam, retaining terrain/buildings/trees/actors/player/model-provider shadows.
- Celestial rotation is continuous in light space; the old rotating-light texel snap is gone.
- Camera stabilization is independent at 1/16 world pixel.
- Recasts use bounded caster-endpoint drift instead of 1/128 light-direction quantization.
- Adaptive resolution is allocation-stable: `available()` cannot resize the map, and a live session does not repeatedly shrink/grow between resolution rungs.
- Explicit depth canvases are attempted first with an implicit-depth fallback. Failed caster/GPU passes are contained and are not published as valid shadow maps.
- Host packed-depth/model/caster-class contracts are preserved exactly.

## Validation boundary

Headless tests validate Lua/source contracts, projection continuity, allocation behavior, failure containment, host API compatibility and package integrity. Final subjective shadow softness and driver-specific framebuffer behavior still require the normal in-game Gen1Recomp playtest.
