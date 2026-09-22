# Weather FX 8.2.0 Final Qualification

Weather FX 8.2.0 is qualified for release from the exact 8.1.99 baseline subject to exact-package replay matching the frozen source checks.

The release intentionally changes only four runtime Lua files. It globally repairs 3D cloud-bank zenith continuity, doubles RAVE volumetric cloud primitives, keeps the RAVE presentation rig active under 2D weather ownership and in battles, and replaces the moving SNOW/BLIZZARD whole-field anchor/handoff with a continuous periodic world-tiled field.

Source qualification is green: 16/16 new regression checks, 13/13 continuous snow-motion checks, 12/12 inherited RAVE/snow continuity checks, 116/116 maintained programs, 195/195 `test_mod`, 80/80 revision gate, and 129/129 runtime Lua compilation. The exact 8.1.99 negative control fails 12/16 new checks as required, demonstrating that the new regression distinguishes the repaired behavior from the baseline.

No particle-count reduction is used to obtain the snow repair; MAX BLIZZARD remains 200,000 flakes. No full 3D weather ownership is forced when RAVE runs with 2D weather.

A fresh interactive framebuffer on the user's exact host/GPU is not available in this environment and is not claimed by this qualification.
