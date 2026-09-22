# Weather FX 8.1.93 — Battle Art 3D NPC Lightning Repair

## Fixed: 3D lightning not reaching NPCs on the current Battle Art voxel fork

Current Battle Art resolves the characters it will actually draw into a private per-frame `posed` list inside `VoxelScene.render()`. That list contains the host-authoritative actor position, support height, animation lift, facing and sprite, but is intentionally **not** assigned to `state.posed`.

Weather FX already had a raw-entity fallback, but on Battle Art that meant NPC lightning was not consuming the same actor stream the host renderer used for the frame. 8.1.93 now uses Battle Art's public `CharacterRenderers.afterActors` extension point as a read-only bridge:

- the bridge runs after Battle Art has resolved the live cast and before Weather FX's wrapped `Voxel3D.endScene()` draws world lightning;
- Weather FX receives the exact host `posed` records and uses them as the NPC-strike authority for that frame;
- host-resolved world position, ground/support height, animation lift and facing are retained for the bolt endpoint and reaction placement;
- Weather FX does **not** call the NPC's `pose()` a second time;
- Weather FX does **not** claim or replace Battle Art's character renderer and returns `false` from the observer callback;
- when the live bridge is available, raw entities that Battle Art did not present are no longer appended as strike candidates;
- older/custom voxel hosts without `CharacterRenderers` keep the existing raw-coordinate fallback.

The player-facing behavior is unchanged: **CHARACTER STRIKES** defaults ON, **STRIKE CHANCE** defaults to 10% per eligible 3D lightning bolt, and a miss/no-candidate event remains an ordinary terrain strike.

## Preserved fixes

- 8.1.92 full-render-distance 3D snow coverage at 100% in both WEATHER FRONTS modes.
- 8.1.91 exclusive local-snow ownership / one-pixel snow-fountain repair.
- 8.1.91 current Battle Art water ownership and compiled host-wave suppression.
- Existing 2D NPC lightning, terrain lightning, burst lightning, RAVE, tornado, cloud/front, celestial, battle and gameplay behavior.

## Qualification

- New Battle Art NPC actor-bridge regression: **8/8 PASS**.
- Exact 8.1.92 negative control: **2/8 PASS, 6/8 FAIL**, proving the new test detects the missing live actor bridge and stale/raw placement path.
- Existing NPC lightning regression: **43/43 PASS**.
- Exact runtime Lua syntax compile: **128/128 PASS**.
- Maintained exact-package developer sweep: **103/103 programs PASS**.
- A fresh real-host/device framebuffer session is still required for final eyes-on confirmation on the user's Battle Art setup.
