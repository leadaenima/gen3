# Weather FX 8.1.98 Final Qualification

Weather FX 8.1.98 is qualified for packaging only when the frozen source and the exact extracted installable ZIP satisfy all of the following:

1. The new RAVE/snow continuity regression passes 12/12.
2. The same regression fails against exact 8.1.97, proving sensitivity to the release changes.
3. RAVE zenith cloud admission remains bounded and ordinary sealed-deck behavior remains intact.
4. Snow fixed-anchor streaming preserves constant authored instance count and no sliding/interpolated anchor while limiting maximum anchor centre lag to 12 world units.
5. Current/root SNOW/BLIZZARD-family ownership prevents a stale distant slab from resurrecting through a transient zero channel, while genuinely distant incoming snow under CLEAR remains visible.
6. Existing 8.1.90/8.1.91 snow-fountain and 8.1.92 full-render-distance regressions remain passing.
7. Revision gate passes 80/80.
8. Maintained developer sweep passes 113/113 programs.
9. `test_mod.py --lua` passes 194/194 with zero failures/skips.
10. All 129 shipped runtime Lua files compile with `texluac -p`.
11. Final ZIP CRC passes with no unsafe paths, duplicate entries, case collisions, or zero-byte regular files.
12. Exact extracted ZIP files are byte-identical to the frozen source tree.
13. Runtime delta versus exact 8.1.97 is limited to `lib/ProceduralSnowField.lua` and `lib/voxel_atmos/CinematicAtmos.lua`.

A real interactive framebuffer is not available in this environment, so subjective RAVE cloud thickness and long-duration live walking remain a player-side visual confirmation rather than a claimed automated screenshot result.
