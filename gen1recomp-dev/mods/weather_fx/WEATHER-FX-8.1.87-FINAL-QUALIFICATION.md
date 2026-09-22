# Weather FX 8.1.87 — Final Qualification

Built directly from exact Weather FX 8.1.86.

## Fixed defects

- RAVE laser spawn centerlines are world/cloud-lattice anchored and no longer change with camera heading, pitch, or orbit.
- The RAVE field covers overhead/near, mid-distance, far-distance, and all four horizontal quadrants.
- Outdoor 3D weather retains its proven pre-battle sky authority through world-backed battle transitions, preventing transient host `outdoor=false` reports from erasing 3D rain/snow/hail/sand/ash/fog/cloud presentation.
- `Battle._startedIndoors` still blocks outdoor weather in real indoor/cave battles.

## Qualification results

- RAVE world-space laser regression: 10/10 PASS.
- 3D battle weather persistence regression: 13/13 PASS.
- Exact 8.1.86 negative control:
  - RAVE laser test: 2 PASS / 8 FAIL, exit 1.
  - Battle persistence test: 6 PASS / 7 FAIL, exit 1.
- Full 8.1.87 source developer sweep: 88/88 programs PASS.
- Clean candidate extraction developer sweep: 88/88 programs PASS.
- Runtime Lua compilation: 123/123 PASS.
- Candidate source/package comparison: 819/819 files, 0 differences.
- Candidate archive structural validation: 819 unique entries, CRC PASS, unsafe paths 0, duplicate entries 0, case collisions 0, zero-byte regular files 0.
- Runtime Lua delta vs exact 8.1.86: exactly two files:
  - `lib/DramalessAtmos.lua`
  - `lib/voxel_atmos/CinematicAtmos.lua`

No fresh live-game framebuffer/device session was captured for 8.1.87; this qualification is executable harness/source/package evidence and does not claim manual visual playtesting.
