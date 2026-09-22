# Weather FX 8.1.54 — Final Release Audit

## Release identity

Weather FX **8.1.54**, “Full-Visual Precipitation Virtualization / Snow Collision Suspension,” is built directly from the exact preserved Weather FX 8.1.53 package (`f861f15107cd544de30f15798543767d77db3ad6b79f041e59e8f9b60c1a883d`).

The intentional runtime delta is restricted to:

- `lib/ProceduralPrecipField.lua`
- `lib/ProceduralSnowField.lua`
- `lib/voxel_atmos/WorldPrecip.lua`

All other frozen runtime files/assets remain byte-identical to 8.1.53.

## Performance change

8.1.54 promotes the existing zero-upload procedural precipitation fields from far-only visual ownership to **complete visual ownership after a real driver proof**. Until the backend successfully performs an invisible instanced draw, Weather FX remains on the complete CPU visual fallback.

After proof:

- rain keeps at most 96 Lua interaction probes while the GPU owns the complete visible rain target;
- snow/blizzard keeps at most 96 Lua face-contact probes while the GPU owns the complete visible snow target;
- hail, sand and ash can use zero CPU visual cards;
- debris/leaves remain fully physical;
- retired CPU particle high-water arrays are compacted to the remaining physical population rather than retained indefinitely.

No authored particle ceiling is reduced. MAX remains rain 12,000 / snow 100,000 / blizzard 200,000 / hail 45,000 / sand 43,200 / debris 3,600 / ash 10,800.

The executable MAX regression proves a 200,000-flake blizzard remains a 200,000-flake visual target while the WorldPrecip Lua allocation/integration pool stays at <=96 probes on the proven GPU path. It likewise proves 12,000 rain remains 12,000 visual drops with <=96 Lua probes. These are workload/state-count guarantees, not fabricated whole-game FPS claims.

## Snow-ground safety change

Falling-snow ground collision is intentionally disabled in 8.1.54 because the current SnowPack ground resolver is not sufficiently reliable. WorldPrecip no longer calls SnowPack collision/settling for falling snow, no longer builds SnowPack support context for snow-only weather, and keeps ground-snow/footprint staging at zero. Falling snow remains visible at the authored logical population.

`lib/SnowPack.lua` remains shipped, bounded and testable so the corrected resolver can be re-enabled in a future revision without losing the established API/retention model.

## Qualification

Release-specific gates completed successfully:

- 8.1.54 runtime delta: exact intended 3-file runtime change;
- 8.1.54 runtime freeze: 162/162;
- 8.1.54 package surface: 20/20 after final-audit inclusion;
- 8.1.54 performance contract: 11/11;
- near precipitation virtualization: 17/17;
- MAX precipitation virtualization: 8/8;
- strict 3D pipeline integrity: 117/117;
- performance invariants: 66/66;
- 8.1.49 player-settings executable suite: 49/49 programs;
- strict full audit: HIGH=0, LOW=0 (manual/robustness MED findings remain documented).

The maintained `tools/run_all.py --lua` command list was executed in four contiguous bounded segments because the complete inherited stress wall exceeds a single execution window. All four segments completed with explicit exit code 0 / `SEGMENT OK` and together cover every command in the maintained runner in order.

## Preserved systems

8.1.54 preserves 8.1.53 spatial cloud/sun terrain lighting; 8.1.52 independent persistent storm fronts, physical distance audio, map persistence and weather authority; 8.1.51 distant-front zero-upload instancing; connected physical water/ice ownership; celestial catalogue/effects; wind; tornado; lightning/NPC lightning; rainbows; battles; encounters; audio and all 68 player settings.

## Verdict

**PASS.** Exact final-ZIP fresh-extraction integrity is recorded separately in the external validation sidecar generated after freeze. Weather FX 8.1.54 supersedes 8.1.53 once that frozen package and its byte-identical Library copy are recorded.
