# Weather FX 8.1.93 Final Qualification

**Status: qualified for packaging, pending user-side visual confirmation on the real Battle Art voxel host.**

Built directly from exact Weather FX 8.1.92. The current Battle Art fork's public `CharacterRenderers.afterActors` stream is now the live actor authority for 3D NPC lightning whenever that API is available. Weather FX receives the exact character records Battle Art already resolved for the frame before world lightning is allocated, so target position, support height, animation lift and facing match the host-rendered NPC without a second `pose()` call.

The observer is read-only and non-owning: it returns false, never replaces Battle Art character drawing and never mutates NPC/gameplay state. Older compatible voxel hosts retain the prior raw-coordinate fallback. CHARACTER STRIKES / STRIKE CHANCE semantics remain default ON / 10% per eligible bolt, with normal terrain targeting on misses or when no eligible NPC exists.

Evidence:
- 8.1.93 Battle Art actor-bridge regression: **8/8 PASS**.
- Existing NPC lightning regression: **43/43 PASS**.
- Exact 8.1.92 negative control: **2/8 PASS, 6/8 FAIL** as expected.
- Exact runtime Lua syntax compile: **128/128 PASS**.
- Maintained exact-package developer sweep: **103/103 programs PASS**.
- 8.1.92 snow-distance, 8.1.91 snow-fountain and Battle Art water ownership gates remain PASS.

No fresh framebuffer/device capture is claimed; the user's Battle Art setup remains the final eyes-on confirmation.
