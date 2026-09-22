# Weather FX 8.2.1 — Mobile 3D Snow Performance Repair

Built directly from exact Weather FX 8.2.0.

## Player report addressed
3D SNOW and every weather family using 3D snow became extremely laggy after the 8.2.0 continuous-field repair. 8.2.1 keeps the no-emitter/no-whole-field-reset behavior but removes the expensive work that made the new field unsuitable for low-powered phones.

## 3D snow performance changes
- Snow quads use **4 unique vertices in one triangle strip** instead of 6 duplicated triangle vertices. This is the same visible quad with **33% fewer vertex-shader executions**.
- The 8.2.0 nearest-periodic-copy equation is rewritten into an algebraically equivalent normalized tile-phase form. Dynamic tile division/floor selection is removed from the per-vertex hot path.
- Tile reciprocal, far-fade reciprocal, patch/front frequencies, vertical field constants and patch-wind normalization are calculated **once per draw on CPU**, not once per snow vertex.
- With a uniform/fronts-OFF field, storm-band trigonometry is skipped completely.
- On GLSL3/native-instance hosts, the old sine-based random hash is replaced with a 32-bit integer bit-mix. The visual distribution remains statistically uniform while removing 15 hash `sin()` evaluations from every snow vertex. Legacy non-GLSL3 hosts keep the established compatibility path.

## Quality and motion explicitly preserved
- SNOW authored ceiling remains **100,000 flakes**.
- MAX BLIZZARD authored ceiling remains **200,000 flakes**.
- Native GLSL3 fields remain **one instanced draw**.
- Fall, tumble, wind drift, sway, depth sizing, cloud/front modulation, snowflake shape and render distance remain active.
- The dedicated presentation clock still advances **every rendered frame**. There is no animation-rate reduction, frame skipping, snapping or low-FPS simulation mode.
- The 8.2.0 no-emitter contract remains: no snapped snow origin, no old/new whole-field handoff, and each flake wraps independently only at its periodic far boundary.

## Deterministic qualification
- 8.2.1 mobile 3D snow regression: **15/15 PASS**.
- Native hash quality: **8/8 PASS** across 200,000 identities and representative shader streams.
- Exact 8.2.0 negative control: **10/15 new mobile checks FAIL**, as required.
- Maintained source developer sweep before freeze: **118/118 programs PASS**.
- `test_mod.py --lua`: **195 passed, 0 failed, 0 skipped**.
- Revision gate: **80/80 PASS**.

No fresh interactive Gen1Recomp framebuffer/GPU session on the user's exact low-powered phone is available in this build environment. The performance changes are structural/hardware-independent workload reductions, not an unverified FPS claim.
