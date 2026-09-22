# Weather FX 8.2.14 — RAVE Removal

Weather FX 8.2.14 removes the former RAVE weather mode from Weather FX itself.

Removed:
- the RAVE weather catalogue and selector entry;
- RAVE MUSIC and RAVE STROBE settings;
- `lib/RaveMusic.lua`, soundtrack playback, and native-BGM ducking;
- bundled `assets/sounds/rave` soundtrack files;
- rave cloud coloration, lasers, illuminated fog, floor lighting, and show synchronization;
- RAVE battle carryover and fallback battle lasers;
- obsolete RAVE-specific test programs.

Compatibility:
- legacy persisted `WEATHER = RAVE` values migrate to `AUTO`;
- standalone Poke Rave is separate and untouched;
- all ordinary Weather FX systems remain available.

Qualification:
- maintained developer sweep: 133/133 programs PASS;
- `test_mod.py --lua`: 202/202 PASS;
- revision gate: 80/80 PASS;
- current voxel-host compatibility: 28/28 PASS;
- dedicated RAVE-removal contract: 16/16 PASS.
