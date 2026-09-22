# Weather FX 8.1.87 — World-Space RAVE Lasers + 3D Battle Weather Continuity

Built directly from exact Weather FX 8.1.86.

## RAVE laser placement repair

RAVE laser emitters are no longer created from the camera-filtered cloud descriptor list. Their centerlines are generated first from a deterministic world/cloud lattice anchored to the player/world position and the live cloud-bank advection. Camera heading and pitch only affect how already-existing beams are viewed/rendered.

This fixes three related symptoms: lasers changing spawn point when the camera moves, lasers appearing only when looking upward, and the active laser field occupying only a small distant patch. The repaired field includes overhead/near, mid-distance, and far-distance emitters across all horizontal quadrants.

## 3D weather persistence into battle

Some voxel battle hosts temporarily report the battle scene as not outdoor even while they continue rendering the outdoor 3D world. `CinematicAtmos.frame()` correctly rejects indoor scenes, so that transient flag could erase all 3D weather on entry to battle.

8.1.87 carries the last proven pre-battle outdoor/sky authority through a world-backed battle. 3D rain and the other 3D weather families therefore remain present across the overworld-to-battle transition. Battles that actually started indoors or in caves remain dry through `Battle._startedIndoors`.

## Qualification

- RAVE world-space laser regression: 10/10 PASS
- 3D battle weather persistence regression: 13/13 PASS
- Negative control on exact 8.1.86: RAVE laser test 2 PASS / 8 FAIL; battle persistence test 6 PASS / 7 FAIL
- Full source developer sweep: 88/88 programs PASS

No fresh live-game framebuffer/device session was captured for 8.1.87; qualification is executable harness/source/package evidence, not a claim of manual visual playtesting.
