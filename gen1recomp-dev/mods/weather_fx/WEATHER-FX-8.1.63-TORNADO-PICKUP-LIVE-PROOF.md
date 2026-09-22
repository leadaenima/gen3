# Weather FX 8.1.63 — Real Tornado Pickup Proof

Qualification stack: Gen1Recomp 0.2.53 / LÖVE 11.5 + user-provided Pokémon Yellow test input + Voxel Nexus 2.0.16 + Weather FX 8.1.63.

## 2D relocation tornado

PASS. Presentation forced to 2D. Weather FX created zero entries in the 3D tornado field. A successful relocation roll created the screen funnel and immediately locked native controls. Real directional input before capture did not move the player. The funnel crossed `approach → sweepout → blackout`; Gen1Recomp made `PALLET_TOWN → VIRIDIAN_CITY` live; during the destination sweep a real UP + START attempt changed neither player coordinates nor menu stack; the funnel completed `sweepin → exit` and controls released.

## 3D ordinary walk-in

PASS. A mature ordinary non-seeker funnel started 32px ahead of the player. Real held-UP input moved the live Yellow player from py=224 to py=222 and into the visible footprint. Weather FX entered `pickup` with reason `player touched active tornado / suction pickup`. The tornado presentation lifted the player from 2.32 to 5.49 world px while right + START input was rejected. Full `pickup → depart → transfer → arrival → landing` completed and Gen1Recomp changed `PALLET_TOWN → VIRIDIAN_CITY`; controls released only after landing.

## 3D NORMAL 10% seeker

PASS after the 8.1.63 navigation repair. Settings reported pickup chance 0.1. A deterministic qualification forces only that random decision to 0.05 (<0.10), then restores production RNG immediately. The resulting real seeker spawned at the configured 150px minimum while the player remained stationary. It closed 150.00 → 0.00 in 484 logic observations, entered pickup without player approach, raised the visible carry pose from 2.00 → 3.88, rejected movement + START, and completed `ROUTE_1 → VIRIDIAN_CITY` before landing/unlock.

The pre-fix real seeker instead stalled around 144–153px because ordinary scenery deflection kept turning it sideways. 8.1.63 retains scenery deflection for ordinary roamers but prevents static scenery from permanently repelling a committed 10% seeker.
