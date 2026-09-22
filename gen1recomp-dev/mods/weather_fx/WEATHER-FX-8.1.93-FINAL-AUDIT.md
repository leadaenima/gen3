# Weather FX 8.1.93 Final Audit

## Scope

Built directly from the exact preserved 8.1.92 source checkpoint. Runtime repair is intentionally limited to 3D NPC lightning actor observation/targeting on current Battle Art plus release/test metadata.

## Player defect

Reported: visible NPCs were not being struck by 3D lightning on the Battle Art voxel fork.

## Repair

- Added a read-only Battle Art `CharacterRenderers.afterActors` observer in `DramalessAtmos`.
- The callback publishes Battle Art's exact per-frame `posed` list to Weather FX before wrapped `Voxel3D.endScene()` executes the 3D atmosphere/lightning pass.
- `NpcLightning` prefers that exact host actor list and does not append raw entities while the bridge is active.
- Target endpoints now use host-resolved position, support height, lift and facing.
- No second NPC `pose()` call is required for strike admission.
- The observer returns false and never owns/replaces character rendering.
- Older hosts keep the existing raw-state fallback.
- NPC/gameplay data is not modified.

## Focused verification

- 8.1.93 Battle Art NPC actor bridge: 8/8 PASS.
- Existing NPC lightning suite: 43/43 PASS.
- Exact 8.1.92 negative control: 2/8 PASS, 6/8 FAIL.

## Full qualification

- Runtime Lua syntax compile: **128/128 PASS**.
- Maintained developer sweep: **103/103 programs PASS**.
- 8.1.92 snow render-distance regression: **8/8 PASS**.
- 8.1.91 snow-fountain regression: **6/6 PASS**.
- 8.1.91 current Battle Art water regression: **5/5 PASS**.

## Preserved behavior

8.1.92 full-distance snow, 8.1.91 one-pixel snow repair, Battle Art water ownership, lightning terrain fallback, configured strike chance, 2D lightning, weather/fronts, clouds, tornadoes, RAVE, celestial, water and gameplay systems remain in scope for the maintained sweep.

## Truth boundary

No fresh interactive Battle Art framebuffer/device session is available in this build environment. Static/executable integration is qualified; final eyes-on confirmation remains user-side.
