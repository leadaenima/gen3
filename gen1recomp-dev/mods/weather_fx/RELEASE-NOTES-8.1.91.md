# Weather FX 8.1.91 — 3D Snow + Battle Art Water Ownership Hotfix

## Fixed: 3D snow collapsing into a one-pixel emitter

8.1.90 removed the secondary visible instancing path, but its distant-front handoff still *faded* the finite snow/blizzard StormCell slab by local intensity. During light and moderate snow, most of that remote slab could remain visible alongside the player-local field. Perspective compresses a distant finite slab into a narrow dense column, producing the reported “snow from one pixel in the sky” look.

8.1.91 changes this from an intensity blend to an ownership handoff. Once the authoritative local snow channel is above the tiny 0.02 noise threshold, player-local WorldPrecip owns nearby snow completely and the distant snow/blizzard slab is suppressed. With no local snow, a genuinely distant snow front remains visible. Rain, fog and lightning front behavior is unchanged.

## Fixed: Weather FX water overlapping current Battle Art water

Weather FX does not edit Battle Art. Both mods are integrated in memory through Battle Art's exported water interfaces. Current public Battle Art now exports `_trainSource`, a helper that older Weather FX logic used as a Voxel Nexus discriminator because the two packages share the `BATTLE_ART_VOXEL_FORK` id. 8.1.90 could therefore classify current Battle Art as the Nexus water lineage.

8.1.91 identifies Voxel Nexus only when its additional `realisticWorld.WaterEngine.tideOffset` seam exists; otherwise a structured `BATTLE_ART_VOXEL_FORK` Water module is treated as public Battle Art.

The physical-water takeover is also hardened against an already-compiled host Water shader. Battle Art bakes `WAVE_HEIGHT` into generated shader source, so changing the Lua field to zero alone cannot alter a shader that was compiled earlier. Weather FX now tracks the relief owner (`host` vs `weather-fx`) and invalidates the host Water shader exactly when that ownership mode changes, after setting `WAVE_HEIGHT=0` for Weather FX physical relief. This removes the host's geometric wave layer while retaining Battle Art's reflection/depth pass on the Weather FX replacement mesh.

## Regression coverage

- Light local snow fully suppresses the distant snow slab; sub-threshold noise and genuinely distant snow remain valid.
- Current public Battle Art with `_trainSource` remains classified as public Battle Art.
- Voxel Nexus remains independently recognized through its WaterEngine tide seam.
- Weather FX physical water explicitly forces host relief to zero and invalidates the host shader on ownership transitions.
- Existing 8.1.90 snow-fountain, public Battle Art and Voxel Nexus water suites continue to pass.

## Visual qualification

The two supplied photos were used to target these failures. No fresh live Battle Art framebuffer/device session is available inside this build environment, so the final visual confirmation still needs an in-game run on the user's Battle Art setup: light/moderate 3D snow should be spatially distributed with no dense point-source column, and Weather FX water should show one physical surface rather than a second Battle Art relief pattern underneath/over it.
