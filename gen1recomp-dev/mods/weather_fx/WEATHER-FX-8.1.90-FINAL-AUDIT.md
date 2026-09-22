# Weather FX 8.1.90 Final Audit

Base: exact Weather FX 8.1.89.

Runtime Lua delta is limited to six files:
1. `lib/DramalessAtmos.lua`
2. `lib/Draw.lua`
3. `lib/EngineRuntime.lua`
4. `lib/Particles.lua`
5. `lib/voxel_atmos/CinematicAtmos.lua`
6. `lib/voxel_atmos/WorldPrecip.lua`

The delta implements feature-aware 2D/3D ownership, strict-3D flat-particle suspension, mixed 2D precipitation + 3D cloud support, connected BLOCKY cloud silhouettes, the 3D snow-fountain ownership repair, and the expanded RAVE atmosphere with coordinated lasers, laser-reactive 3D fog, moving-head ground light pools, and a synchronized master sky/atmospheric color cue.

Maintained Lua wall: 88/88 PASS. Aggregate validator: 192/192 PASS. Structural/performance/host gates are listed in the final qualification.

No fresh framebuffer/device playtest was performed; no visual claim is made beyond executable renderer/state evidence.
