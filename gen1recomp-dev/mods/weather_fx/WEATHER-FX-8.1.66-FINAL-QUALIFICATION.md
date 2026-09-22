# Weather FX 8.1.66 — Final Qualification

## Release decision

**PASS — frozen candidate qualified for package creation.**

8.1.66 is built directly from exact Weather FX 8.1.65 (`c5531191698a62ec50370f5da746b04cc832300db553faef154615a40dc473f1`) and changes snow accumulation presentation from detached raised-surface caps to world-positioned repaint of the actual voxel host geometry.

## Exact runtime delta

Behavioral runtime delta from 8.1.65 is exactly:

- `lib/SnowPack.lua`
- `lib/DramalessAtmos.lua`
- `lib/voxel_atmos/WorldPrecip.lua`
- new `lib/SnowSurfacePaint.lua`

All other inherited runtime paths are frozen byte-identical. Current runtime freeze: **164/164 PASS**.

## Surface-conformal snow proof

- Snow surface repaint executable: **24/24 PASS**.
- Exact Voxel Nexus tree-hull regression: **5/5 PASS**.
- Static/integration repaint contract: **15/15 PASS**.
- Exact Voxel Nexus 2.0.17 host contract: **11/11 PASS**.
- Exact 8.1.65 negative control: repaint contract **1/15**, tree-hull regression **0/5** as expected.
- Raised/tree/roof/ledge surfaces generate no detached snow-bank cap geometry; ground/grass/load-bearing ice retain physical thickness.
- Voxel Nexus round/tree collision uses the same `Structures.roundStamps` quads that `ChunkMesher` submits to the visible terrain mesh.
- World-position coverage keeps identical geometry elsewhere untouched.
- Melt is authoritative through SnowPack depth decay; when depth reaches zero the repaint disappears and the untouched host material is revealed.

## Snow / weather regression

- SnowPack live restore: **7/7 PASS**; restore contract **8/8 PASS**.
- Snow accumulation/footprints: **14/14 PASS**.
- Snow radial surfaces: **10/10 PASS**.
- 3D snow bank/water: **7/7 PASS**.
- Snow on ice: **5/5 PASS**.
- Snow virtualization: **10/10 PASS**.
- Fixed-world snow motion: **10/10 PASS**.
- Existing 8.1.65 remote tornado contract: **12/12 PASS**; executable roaming **12/12 PASS**; render cull **4/4 PASS**; maintained 3D Gale tornado **38/38 PASS**.

## Whole-mod gates

- `test_mod.py --lua`: **191/191 PASS**.
- Performance invariants: **66/66 PASS**.
- 3D pipeline integrity: **117/117 PASS**.
- Feature integrity: **505/505 PASS**.
- Current voxel-host contract: **27/27 PASS**.
- Aggressive compatibility: **30 PASS / 0 MED / 0 HIGH**.
- Benchmark: **26/26 PASS + 24/24 integration PASS**.
- LuaJIT update headroom: **49 estimated direct upvalues / 60 hard limit**, under 55 ship guard.
- Scope hygiene: **PASS**.
- LÖVE sandbox static scan: **125 shipped runtime Lua files PASS**.
- Edit guard: **PASS**.
- AI debug: **FAIL=0 / WARN=0**.
- Full audit: **HIGH=0**, six MED manual/robustness boundaries.

## Qualification boundaries

`tools/release_deep_audit.py` exceeded the bounded execution window after a long clean prefix and is **not counted as a pass**. The changed 8.1.66 paths are instead covered by the focused executable regressions, exact Voxel Nexus 2.0.17 source contract, whole-mod Lua suite, performance/3D/compatibility/sandbox gates, and frozen-package replay.

The historical `tests/world_precip_sim_test.lua` timeout is inherited from exact 8.1.65 and is not counted as a pass.

No new physical GPU/LÖVE framebuffer capture is claimed in this environment. The changed repaint GPU path is exercised with a deterministic graphics mock and exact Voxel Nexus host-source contracts; inherited live visual evidence applies only to byte-identical presentation paths.
