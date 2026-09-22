# Weather FX baseline

Current source baseline: **8.2.14**.

8.2.14 is the RAVE-removal release built directly from exact Weather FX 8.2.13.

This release removes the former RAVE weather mode completely from Weather FX: its manual weather catalogue/selector entry, RAVE MUSIC and RAVE STROBE settings, `RaveMusic` audio ownership and native-music ducking, bundled rave soundtrack, 3D rave cloud/laser/fog/floor show, battle carryover, and obsolete RAVE-specific regression programs.

Legacy saves that still contain `WEATHER = RAVE` migrate to `AUTO`, preventing an invisible removed weather mode from remaining active after upgrade. The standalone Poke Rave mod is separate and is not changed by this Weather FX release.

All non-RAVE Weather FX systems remain qualified, including Gen1/Gen2 support, 2D/3D weather, cloud banks, precipitation, snow/accumulation, lightning, tornadoes, water, seasons, battles, celestial rendering, ordinary weather audio, and performance controls.
