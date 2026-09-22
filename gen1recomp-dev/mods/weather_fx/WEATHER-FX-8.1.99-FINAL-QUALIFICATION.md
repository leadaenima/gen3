# Weather FX 8.1.99 Final Qualification

Weather FX 8.1.99 is release-qualified when the frozen source and exact extracted installable ZIP satisfy all of these gates:

1. Native BLIZZARD instance-ID regression: **12/12 PASS**.
2. Combined 2D weather repair regression: **14/14 PASS**.
3. 2D celestial world-lock and zenith regressions remain passing.
4. 2D weather style/options/restart regressions remain passing.
5. Existing 2D and 3D lightning regressions remain passing.
6. New **2D WEATHER LIGHTNING** setting is unique, described, persisted, and runtime-consumed; schema total is **80** player controls.
7. Simultaneous maximum-settings profile remains valid.
8. All shipped runtime Lua compiles with `texluac -p`.
9. Maintained developer sweep passes **115/115 programs**.
10. `test_mod.py --lua` reports **195 passed, 0 failed, 0 skipped**.
11. ZIP CRC/path/duplicate/case/zero-byte integrity passes.
12. Exact source/package compare is byte-identical.
13. Runtime delta versus exact 8.1.98 is limited to the seven intended files documented in the final audit.

A live interactive framebuffer session is not available in this environment and is not falsely claimed.
