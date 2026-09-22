# Weather FX 8.1.95 Final Qualification

**Status: fully qualified for release.**

Weather FX 8.1.95 fixes the weak RAVE illuminated-fog presentation and re-qualifies the production strobe on the user-supplied Battle Art Voxel Fork 1.10.4.

Pre-freeze evidence:
- **13/13 PASS** focused RAVE fog/strobe regression.
- **107/107 programs PASS** maintained developer sweep.
- Real Battle Art 1.10.4 framebuffer run: 40 fog volumes, 80 beam-hit fog vertices, 19/19 successful fog draw observations, and strobe 56 -> 0 -> 56 fixtures.
- Real framebuffer captures exist for illuminated fog and strobe ON/OFF/return.

Final exact-package gates PASS: clean ZIP integrity/source comparison, 107/107 maintained developer programs, 13/13 focused RAVE fog/strobe checks, 47/47 song/BPM/package synchronization, 8/8 target LÖVE 11.5 OGG decodes, and 128/128 runtime LuaJIT syntax compilation. The final package is preserved with sidecar checksum and validation evidence.
