# Weather FX 8.1.72 Final Qualification

**QUALIFIED by executable and exact-package regression gates.**

The new in-game **3D WEATHER DISTANCE** setting is default 100% and exposes only 25/50/75/100% values. With WEATHER FRONTS OFF, the resulting rain/snow/hail WorldPrecip radius is the live voxel far distance multiplied by the selected value; at 100% it is exactly the voxel distance. The setting never modifies Voxel3D/world render distance. WEATHER FRONTS ON retains the inherited regional/front-owned reach.

The inherited snow-fountain/hail-tube procedural fail-open protection and snow accumulation setting remain covered by passing regressions.

No fresh live-game framebuffer capture was produced for 8.1.72 in this pass; qualification is based on executable runtime tests and exact-package replay.
