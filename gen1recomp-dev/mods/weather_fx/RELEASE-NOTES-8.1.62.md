# Weather FX 8.1.62 — Tornado Walk-In Contact

## What was still broken

8.1.61 repaired the actual cross-map transfer once tornado pickup had begun, but its strongest 3D contact test initialized a mature funnel directly on the player's coordinates. That proved transfer, not real walk-in collision. In normal play a player can enter the visibly rotating ground circulation without their anchor point ever entering the old 14-world-pixel contact core, and some voxel hosts may expose a render-state player snapshot that lags or copies the live gameplay entity.

## Contact repair

8.1.62 keeps the existing carry state machine and changes only how a mature 3D funnel recognizes physical player contact:

- the live overworld player is the first gameplay position authority; the voxel render snapshot is fallback only;
- visible ground-circulation overlap counts as contact. The effective physical envelope is at least 30 world pixels, covering the rendered ~21px debris/spray footprint plus the player's body instead of requiring the anchor to enter the old 14px core;
- swept relative-motion collision checks the interval between consecutive player/tornado samples so fast movement cannot tunnel through the funnel;
- contact is map-scoped, preventing a stale player sample from a different map from producing a false pickup;
- the random CARRY CHANCE remains the seeker/hunting probability. Direct collision with a mature active funnel does not reroll that chance.

## Reproduction added

A new walk-in regression deliberately keeps the voxel player snapshot stale, starts the real gameplay player outside the tornado, moves them into the visible outer ground circulation rather than the exact centre, and requires the full pickup/depart/transfer/arrival/landing sequence to end on a different live map. It also tests a fast swept crossing whose endpoints are both outside the contact radius.

The untouched exact 8.1.61 Tornado.lua fails 5/8 checks in this new reproduction. The 8.1.62 implementation passes 8/8.

## Preserved

8.1.61 direct live Gen1 `setMap` / Gen2 `warpToMapId` transfer verification, 2D tornado relocation, escape-safe visited destinations, Surf safety, blackout/arrival choreography, persistent roaming funnels, waterspouts, NPC lightning, precipitation, clouds, water, celestial systems, settings, audio and performance architecture remain unchanged outside `lib/Tornado.lua`.

## Real Gen1Recomp walk-in qualification

The final candidate was also exercised in the preserved real stack: Gen1Recomp 0.2.53 / LÖVE 11.5, the user-provided Pokémon Yellow input, and exact Voxel Nexus 2.0.16. Weather FX reported `GALE`, `TORNADOES=ON`, and a true 3D presentation. Viridian City was genuinely visited first, then the player was placed in Pallet Town outside a stationary mature ordinary funnel's physical envelope.

A real held **UP** input moved the live overworld player from `py=224` to `py=222`. Before a full tile step completed, contact with the visible funnel footprint changed the tornado to `pickup` with reason `player touched active tornado / suction pickup`. The ordinary (non-seeker) contact path chose the previously visited safe destination, completed departure and transfer, and Gen1Recomp's real map loader changed the live map from `PALLET_TOWN` to `VIRIDIAN_CITY`. No map-transfer stub was used.
