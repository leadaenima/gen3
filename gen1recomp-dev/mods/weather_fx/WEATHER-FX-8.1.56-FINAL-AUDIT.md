# Weather FX 8.1.56 — Final Release Audit

## Release identity

Weather FX **8.1.56**, “Seamless Battle Precipitation Handoff”, is built directly from exact preserved Weather FX 8.1.55.

## Runtime repair

Production runtime changes are restricted to:

- `lib/voxel_atmos/WorldPrecip.lua`
- `lib/BattleDraw.lua`
- `lib/Scene.lua`
- `main.lua`

The failure was a battle-transition ownership race. WorldPrecip used a one-second cached Scene battle check and evaluated it only after stream/focus handling. During battle entry, the battle camera/focus could therefore shift the outgoing overworld snow field into view, creating a sudden heavy burst. When the cache finally observed the battle, the world field stopped; BattleDraw then eased its separate battle snow from zero, producing the visible dump → stop → restart sequence.

8.1.56 makes battle ownership frame-live through `Battle.current()` with Scene fallback, suspends WorldPrecip before any focus/stream re-anchor, suppresses stale WorldPrecip drawing during battle authority, suppresses the flat outgoing precipitation layer during battle-opening frames, and primes BattleDraw from the finalized `battle.field.weather`. Mid-battle move/ability weather still uses the existing eased transition.

## Preserved behavior

- 8.1.55 fixed-world snow anchors and monotonic presentation clock are unchanged.
- Snow/blizzard density and authored particle ceilings are unchanged.
- 8.1.54 full-visual GPU precipitation virtualization is unchanged.
- MAX blizzard remains 200,000 visual flakes with <=96 Lua snow probes on the proven GPU path.
- MAX rain remains 12,000 visual drops with <=96 Lua interaction probes on the proven GPU path.
- Snow ground collision/settling/banks/footprints remain intentionally disabled.

## Qualification

Working-tree qualification:

- all shipped Lua units parse successfully;
- all shipped Python units parse successfully;
- 8.1.56 runtime delta: PASS;
- 8.1.56 runtime freeze: 162/162 PASS;
- 8.1.56 package surface: 9/9 PASS;
- 8.1.56 battle precipitation source contract: 8/8 PASS;
- executable battle precipitation continuity: 6/6 PASS;
- inherited 8.1.55 snow motion: 10/10 PASS;
- inherited 8.1.54 near precipitation virtualization: 17/17 PASS;
- inherited 8.1.54 MAX virtualization: 8/8 PASS;
- strict 3D pipeline integrity: 117/117 PASS;
- headless Lua/mod suite: 191/191 PASS;
- complete maintained `tools/run_all.py --lua` command list covered in five contiguous bounded segments, each with explicit exit code 0.

Final exact-package validation is recorded in `weather_fx-core-8.1.56-validation.txt`.
