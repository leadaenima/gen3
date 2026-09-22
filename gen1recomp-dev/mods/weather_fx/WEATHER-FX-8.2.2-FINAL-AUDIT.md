# Weather FX 8.2.2 Final Audit

## Scope

8.2.2 is built directly from exact Weather FX 8.2.1. It addresses two user-observed release blockers: all weather families using 3D snow becoming unplayably slow even at the lowest quality tier, and the 3D cloud bank plus sun/moon disappearing at steep upward camera pitch.

## 3D snow performance repair

The primary low-setting defect was architectural rather than a raw particle-count problem. Low nonzero snow populations could stay on the legacy CPU simulation/dynamic-mesh path because procedural full-visual ownership was gated by population. 8.2.2 allows every nonzero 3D snow population to use the proven procedural renderer and probes it before any legacy visible CPU snow mesh is constructed.

For devices without usable instancing, the renderer now has an immutable 4,096-flake GPU page fallback. Snow positions, fall, wind drift, sway, tumble and periodic world continuity stay in the vertex shader; ordinary mesh pages are reused rather than rebuilt/uploaded every frame. Native GLSL3/instance-ID hosts retain the one-draw full-population path.

The shader hot path is also reduced without lowering authored density or animation cadence: the flake fragment shape removes atan/length/sin work, billboard axes are calculated once per draw, periodic sway/tumble uses a continuous trig-free turn approximation, storm-band modulation is transcendental-free, and the direct integer-ID path packs random lanes from five integer mixes. The 100,000 SNOW and 200,000 MAX BLIZZARD ceilings remain unchanged.

## Zenith cloud / celestial repair

Cloud billboards now prefer a basis recovered from the live view-projection matrix. This remains valid at exact zenith where a camera-up cross-product can collapse. Camera-vector fallbacks remain for hosts that do not expose a usable VP matrix.

Sun/moon direction projection now prefers a complete perspective VP matrix, so camera pitch is included even on hosts whose `lookFlat` is horizontal-only. Identity/non-perspective compatibility matrices fall back to the prior direction-basis projector; the existing constellation/planet submission regression remains passing.

## Executed source qualification

- 8.2.2 mobile-snow + zenith-sky regression: **24/24 PASS**.
- Maintained developer sweep: **119/119 programs PASS**.
- `test_mod.py --lua`: **195 passed, 0 failed, 0 skipped**.
- Revision gate: **80/80 PASS**.
- Runtime Lua compile: **129/129 PASS**.
- Exact 8.2.1 negative control: **19/24 new checks fail**, as required.

## Candidate package replay

Before final documentation was embedded, the frozen 915-entry candidate ZIP was extracted and replayed through the same executable wall:

- 8.2.2 focused regression: **24/24 PASS**.
- Maintained developer sweep: **119/119 programs PASS**.
- `test_mod.py --lua`: **195 passed, 0 failed, 0 skipped**.
- Revision gate: **80/80 PASS**.
- Runtime Lua compile: **129/129 PASS**.

The final ZIP is replayed again after these audit documents are included; its package identity and final results are published in the external validation record.

## Truth boundary

This environment cannot execute a fresh interactive Gen1Recomp session on the user's exact low-powered phone or desktop GPU. 8.2.2 therefore claims verified architectural workload removal, executable invariants and package replay—not a fabricated FPS number. Live device play remains the final performance/visual measurement.
