# Weather FX 8.1.94 Final Qualification

**Status: qualified for packaging.**

Weather FX 8.1.94 gives each of the eight bundled RAVE songs its own authored light show and drives that show from the song's real streamed decoder playhead at the song's exact BPM. Downbeats/offbeats, beam gates, floor pools, fog illumination, cloud pulses and sky/ray washes therefore remain musically synchronized instead of running on one global visual BPM.

Exact song clocks are 134, 142, 150, 160, 140, 150, 124 and 128 BPM for Neon Conveyor, Steel Pulse, Pixel Rush, Laser Floor, Voxel Wobble, Subspace Drop, Route 4 AM and Moonlit Club respectively. The eight songs use eight distinct choreography profiles, with arrangement-level pullbacks and accents aligned to their own breakdown/drop/return bars.

Evidence:
- **47/47 PASS** song/BPM/package synchronization.
- **40/40 PASS** per-song executable light-show coverage.
- **24/24 PASS** RAVE music shuffle/ownership coverage.
- **24/24 PASS** existing RAVE weather regression.
- **22/22 PASS** existing RAVE show regression.
- **8/8 PASS** target LÖVE 11.5 OGG decoder qualification.
- **128/128 PASS** runtime LuaJIT syntax compile.
- **106/106 programs PASS** maintained developer sweep.

No new live gameplay RAVE framebuffer capture is claimed; qualification is based on target-runtime decoding plus executable timing/choreography and full maintained regression coverage.
