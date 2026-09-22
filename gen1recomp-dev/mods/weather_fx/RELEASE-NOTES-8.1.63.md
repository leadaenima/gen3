# Weather FX 8.1.63 — Tornado Pickup Ownership / Committed Seeker

## What is fixed

- **2D remains screen-space only.** No 3D/world-space tornado is created in 2D presentation. When the configured pickup chance succeeds, controls lock before the funnel approaches, the funnel sweeps left-to-right, carries the player through blackout to a different proven-safe visited map, sweeps the player into the destination, then releases controls.
- **3D walk-in pickup is physical.** Walking into the visible footprint of an ordinary mature roaming funnel triggers suction/pickup independently of the 10% seeker roll.
- **3D seeker is now committed.** The NORMAL 10% roll creates one seeker at the normal 150–250px spawn distance. It homes toward the live player and static scenery can no longer kick it sideways forever. Ordinary non-seeker tornadoes retain scenery deflection.
- **Native control ownership is complete.** Weather FX asserts `player.inputLocked` for the full 2D sweep and 3D pickup/carry/landing and also guards Gen1Recomp's overworld input seam, preventing directional input, Voxel Nexus FreeMove, A, or START from being accepted during carry—including the frame after `setMap` reconstructs/reset player state.
- **Pickup matches the visible funnel.** Both walk-in contact and committed seeker capture use a minimum 30px physical footprint instead of an invisible 13–14px centre bullseye.

## Real-runtime qualification

Using preserved Gen1Recomp 0.2.53 / LÖVE 11.5, the preserved user-provided Pokémon Yellow input, and exact Voxel Nexus 2.0.16:

- **2D:** zero 3D tornado objects; `approach → sweepout → blackout → sweepin → exit`; Pallet Town → Viridian City; real UP + START attempts rejected during source and destination carry; controls restored after drop.
- **3D walk-in:** ordinary non-seeker at 32px; real held UP moved the player into the footprint (`py 224 → 222`); pickup began with `player touched active tornado / suction pickup`; visible lift increased `2.32 → 5.49`; movement + START rejected; Pallet Town → Viridian City; controls restored after landing.
- **3D seeker:** NORMAL pickup chance verified as 0.10; seeker spawned at exactly 150px; with the player stationary it closed `150 → 0` in 484 logic observations, began pickup by itself, visible lift increased `2.00 → 3.88`, movement + START were rejected, and Route 1 → Viridian City completed before landing/unlock.

The permanent 8.1.63 regression deliberately marks the seeker's entire approach corridor as solid scenery. Exact 8.1.62 fails that corrected pickup-semantics test (11 failures); 8.1.63 passes 20/20.
