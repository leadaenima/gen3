# Weather FX 8.1.97 Final Qualification

The release is qualified only after the frozen installable ZIP is extracted to a clean directory and the exact extracted bytes pass package integrity, source comparison, runtime Lua compilation, the complete settings audit, maintained developer sweep, and package-level settings/RAVE regressions.

Required final gates:

1. ZIP CRC passes with no unsafe paths, duplicate entries, case collisions, or zero-byte regular files.
2. Extracted package files are byte-identical to the frozen source tree.
3. Runtime Lua compiles under the target `texlua` syntax gate.
4. Final schema contains exactly 79 unique player-facing keys and 79 unique labels, with every control in exactly one submenu.
5. Complete player-settings interaction audit passes 2298/2298.
6. Settings runtime/advanced/menu/descriptions/live-chain audits all pass.
7. `player_settings_dedup_rave_8197_test.lua` passes 16/16.
8. RAVE music regression passes 24/24 and per-song BPM/light-show regression remains passing.
9. Simultaneous maximum-settings profile remains valid.
10. Maintained 8.1.97 developer sweep passes 112/112 programs.
11. `test_mod.py --lua` passes 193/193.
12. Existing 8.1.96 pause-menu weather, 8.1.95 RAVE illuminated fog/strobe, 8.1.93 Battle Art NPC lightning, 8.1.92 snow render-distance, and 8.1.91 Battle Art water ownership regressions remain passing.

Final release records store the ZIP checksum, exact-package validation, full-settings audit, uniqueness audit, maintained developer sweep, runtime compile log, runtime delta, and source/package comparison alongside the installable ZIP.
