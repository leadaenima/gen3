# Weather FX 8.1.96 Final Qualification

Release is qualified only after the frozen installable ZIP is extracted to a clean directory and the exact extracted bytes pass package integrity, byte comparison, target LuaJIT compile, pause-menu focused regression, maintained developer gates, and the existing RAVE/audio/host compatibility regressions.

Required final gates:

1. ZIP CRC passes with no unsafe paths, duplicate entries, case collisions, or zero-byte regular files.
2. Extracted package files are byte-identical to the frozen source tree.
3. Runtime Lua compiles under target LuaJIT/texlua tooling.
4. `pause_menu_weather_8196_test.lua` passes 23/23.
5. Maintained 8.1.96 developer sweep totals 108/108 programs PASS.
6. `test_mod.py --lua` passes 193/193.
7. Existing RAVE song/BPM/light-show synchronization, illuminated fog/strobe, NPC lightning, snow render-distance, Battle Art water ownership, precipitation/fronts, tornado, celestial, audio, battle, season, settings and performance/compatibility guards remain passing.
8. Real framebuffer evidence confirms 2D rain behind START, animated pause behavior, pixel-stable FROZEN behavior, and immediate resume after START closes.

The final release record stores the ZIP checksum, validation log, developer-sweep log, runtime compile log, runtime-delta proof, live QA log and framebuffer evidence package alongside the installable ZIP.
