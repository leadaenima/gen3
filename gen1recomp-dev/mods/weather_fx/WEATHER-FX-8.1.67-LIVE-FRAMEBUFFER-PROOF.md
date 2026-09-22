# Weather FX 8.1.67 — Live Snow/Ledge Framebuffer Proof

## Runtime provenance

This qualification used the preserved **Gen1Recomp 0.2.53 Linux x86_64 AppImage** (embedded LÖVE 11.5 / LuaJIT), the preserved user-provided Pokémon Yellow test input, exact **Voxel Nexus 2.0.17**, and the 8.1.67 candidate runtime code that became the final nine-file runtime delta. At capture time the pre-freeze manifest still printed `weather_fx 8.1.66` in the host log; the runtime behavior under capture was the 8.1.67 hotfix branch, and no runtime file was changed after this accepted `final2` capture. Subsequent changes were release identity, tests, audit documentation and package evidence only.

The live game was rendered at **1024×768** under Xvfb with llvmpipe software OpenGL. The PNGs listed below are direct LÖVE framebuffer captures; they are not generated or painted reference images.

## Real Route 4 support proof

The live source map is Route 4. The voxel support resolver reported ordinary adjacent ground at Y=0 and the authored Route 4 ledge tiles at **Y=6** with `raised / ledge / top / full` support.

Representative live points:

- `(228,152)` -> Y=6, raised ledge
- `(232,152)` -> Y=6, raised ledge
- `(236,152)` -> Y=6, raised ledge

This is the rendered/collision support used by SnowPack; no guessed tile-to-world conversion is used for the final proof.

## Frame sequence

- `final2_ledge_00_clear.png` — clear baseline.
- `final2_ledge_01_falling.png` — real SNOW_LIGHT field falling over the same scene.
- `final2_ledge_02_mid.png` — accumulated snow with raised-surface repaint active.
- `final2_ledge_03_heavy.png` — later/heavier accumulated state.
- `final2_ledge_04_melted.png` — post-snow melt-back.

SHA-256:

- clear: `d0cf2ff6885f7150ebc5223173690f544834dcbe077685743bd7180ac18ce05f`
- falling: `82ee81dbb16249a5f70b85be9e7dc39514a9056c79c7db735da168637138d24f`
- mid: `add4c1fabbc4fa0750a4aa29791c9978d29054f95929bd0de239c0f997ac10cd`
- heavy: `03b90c466579a3c6f81d5a5c1ebd403f4ad471a0c029e4af39ea7662b8db684c`
- melted: `67b8e359e1528081644b0a85616f3b471a7706241384afcd79056ec7e5f09077`

## Live repaint / melt diagnostics

The same run recorded raised-surface SnowSurfacePaint coverage at the proven Y=6 ledge. Representative values include:

- mid: `(228,152)` coverage `0.23990004164931`, surface Y=6, raised profile `0.38`;
- heavy: `(236,152)` coverage increased from `0.037090718345935` to `0.11535525034786`, surface Y=6;
- heavy repaint field: 256 coverage texels / 418 repaint draws recorded by the live diagnostic;
- after melt: SnowPack cells=0, patches=0, repaint population=0.

The live log is preserved with the framebuffer evidence as `ledge_final2.log`.

## Important qualification note

For visual qualification, accumulation/melt progression was accelerated after the real snow field was active so the complete clear -> falling -> accumulated -> melted sequence could be captured in one bounded run. The world renderer, Voxel Nexus terrain/ledge geometry, Weather FX SnowPack collision/support, snowfall draw path and SnowSurfacePaint renderer were the real production paths. The acceleration does not substitute fake geometry or a mock framebuffer.

A later redundant first-person close-up cold boot was stopped after approximately nine minutes while Voxel Nexus was still scanning its large private model bank; no frame from that incomplete attempt is counted as evidence.
