# Weather FX 8.1.61 — Final Audit

## Release purpose

Weather FX 8.1.61 repairs the original shared tornado carry implementation so both the flat 2D GALE tornado and strict 3D tornado make the destination map become the live overworld instead of merely starting/accepting a warp request.

## Runtime delta

Built directly from the exact Weather FX 8.1.60 package. The intended gameplay-runtime delta is exactly one existing runtime file:

- `lib/Tornado.lua`

No precipitation, cloud, water, lightning, celestial, audio, settings, performance, NPC, or rendering runtime module is changed by this release.

## Transfer repair

The shared `T._warpTo` authority now:

- resolves the real live overworld;
- uses Gen1's live `setMap` primitive first;
- uses Gen2's live `warpToMapId` primitive when present;
- accepts a synchronous transfer only when the requested destination is actually the live map afterward;
- keeps public `mod.world:warpTo` and private `startWarpTo` only as compatibility fallbacks;
- clears stale Surf presentation before a land transfer while retaining existing water/Surf safety.

Both 2D and 3D carry continue to route through the same repaired `T.carry` / `T._warpTo` path.

## Visited-map repair

Tornado destination enumeration now treats Weather FX's own persisted, validated `tornadoLandings` as the authoritative record of outdoor maps actually observed by Weather FX. Engine `save.visited` entries remain merged for compatibility. This avoids treating Gen1Recomp's fly-town visit flags as a complete history of every visited outdoor map.

Every destination still has to pass the existing current landing and escape-safety proof, current-map exclusion, outdoor requirement, and Surf requirement where applicable.

## Qualification

Current-release gates:

- 8.1.61 runtime delta: PASS — exactly `lib/Tornado.lua` differs from the 8.1.60 runtime snapshot;
- 8.1.61 runtime freeze: PASS 163/163;
- 8.1.61 package surface: PASS 11/11;
- 8.1.61 transfer contract: PASS 10/10;
- hostile real-transfer regression: PASS 5/5.

The hostile regression deliberately makes the public warp API return success while doing nothing. It verifies that both the 2D and 3D tornado still make the destination map live through the direct transfer path, and that a Weather FX-remembered non-fly outdoor map remains eligible even when the engine visit table omits it.

Maintained tornado behavior:

- 2D relocation runtime 8.1.58: PASS 8/8;
- relocation choreography: PASS 7/7;
- framebuffer blackout: PASS 8/8;
- 3D relocation/contact: PASS 8/8;
- waterspout presentation: PASS 5/5;
- safe destinations: PASS 23/23;
- 3D Gale tornado: PASS 38/38;
- tornado map persistence: PASS 10/10.

Preserved 8.1.60 NPC-lightning behavior:

- static contract: PASS 20/20;
- executable 2D behavior: PASS 15/15.

The maintained whole-mod runner is longer than this environment's single-command execution ceiling, so it was exercised in overlapping bounded segments. The initial segment reached the 8.1.22 gates with no failures; the middle segment re-ran the inherited gates through 8.0.5 with no failures; explicit 8.0.6/8.0.7 gates passed 10/10, 43/43 and 12/12; the tail segment from 8.0.8 through the final compatibility/audit tools completed with `all ok — safe baseline for next revision`. A legacy 8.1.1 static string check was updated to recognize the refactored equivalent safe-landing predicate; its behavioral requirement is unchanged and it passes 21/21.

The historical 8.1.57 2D choreography test retains two already-obsolete expectations and fails the same two checks on untouched 8.1.60; it is not counted as a new 8.1.61 failure. The maintained 8.1.58 replacement choreography/relocation suites above are green.
