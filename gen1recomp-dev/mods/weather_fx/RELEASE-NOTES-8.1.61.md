# Weather FX 8.1.61 — Tornado Real Map Transfer

## What was actually broken

The tornado choreography could begin correctly while the shared carry bridge still failed to make another map become the live overworld. Both 2D and 3D tornadoes use the same `T.carry` / `T._warpTo` authority, so the defect affected both presentations.

Two implementation assumptions were unsafe:

1. a public/queued warp request could be accepted as a successful carry before the destination map was proven live;
2. Gen1Recomp's `save.visited` was treated as complete map history even though it is primarily the fly-town visit table, excluding ordinary outdoor routes and other visited maps.

## Real transfer repair

8.1.61 resolves the live overworld and uses the engine's real synchronous map-change primitive first:

- **Gen1:** the tornado calls the live overworld `setMap`, the same loader reached by the normal engine warp transition at its midpoint;
- **Gen2:** the tornado calls the live `warpToMapId` path;
- the transfer is accepted only when the live overworld reports the requested destination as its active map;
- the existing public `mod.world:warpTo` and private `startWarpTo` routes remain compatibility fallbacks when the direct live primitive is unavailable.

The tornado already supplies its own departure/blackout/arrival presentation, so the direct map swap prevents an unrelated second engine fade from being stacked underneath the tornado sequence. A land landing also clears stale Surf presentation state before the swap; water landings keep the existing Surf eligibility and activation rules.

## Real visited-map history

Weather FX already records a validated escape-safe landing whenever it observes the player on an eligible outdoor map. 8.1.61 now uses those persisted `tornadoLandings` as the authoritative tornado visit history and merges the engine visit flags for compatibility with older saves.

A destination must still:

- be different from the current map;
- be outdoors;
- have a currently valid escape-safe landing;
- obey Surf requirements for water landings;
- remain reachable/escapable under the existing safety proof.

## Qualification

A new hostile regression deliberately makes the public warp API return success while doing nothing. The test also omits the destination from the engine fly-town visit table while retaining Weather FX's genuine remembered outdoor landing. Under those conditions:

- the 2D tornado changes the live map;
- the 3D tornado changes the live map;
- neither path trusts the lying public warp when a proven live synchronous transfer is available;
- the non-fly remembered outdoor map remains eligible.

The maintained 8.1.58+ tornado relocation, safe-destination, persistence and waterspout suites remain mandatory. The old 8.1.57 choreography test has two historical expectations already failing in the untouched 8.1.60 package and is not used as evidence for this repair.

## Preserved

8.1.60 2D NPC lightning / visible strike smoke, 8.1.59 snow point-plume repair, tornado safety rules, 2D blackout/arrival choreography, 3D roaming/contact behavior, waterspouts, weather settings, precipitation, water, clouds, lighting, celestial systems, audio and performance architecture are unchanged except for the shared tornado transfer authority described above.
