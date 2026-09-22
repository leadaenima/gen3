# Weather FX 8.2.6 Final Audit

## Scope

8.2.6 is built directly from exact Weather FX 8.2.5. The target is the complete Weather FX stack on both low-powered phones and a 16 GB desktop at MAX settings, preserving smooth animation, authored weather density and visual quality rather than solving performance through broad effect reduction.

## Root causes corrected outside snow

1. Low-count rain could remain on the legacy CPU-visible path even when the procedural GPU backend was healthy.
2. Hail, sand and ash used a similar `>1200` virtualization threshold, allowing low tiers to pay CPU simulation/mesh costs unnecessarily.
3. Failed/unsupported procedural precipitation could inherit large logical world populations on the CPU.
4. The shared procedural precipitation carrier used six vertex shader executions for a four-corner quad and retained avoidable transcendental math in hashing, wander/storm modulation and ash fragment shaping.
5. Puddle reflection scans allocated new descriptor tables repeatedly while examining the same bounded neighborhood.

## Repairs

- Proven GPU rain/hail/sand/ash owns every nonzero visual population.
- GPU-failure/unsupported CPU-visible fallback is capped by the existing quality budgets before simulation allocation.
- Leaves/debris remain physical and collision-capable.
- Shared procedural precipitation uses a four-vertex strip and continuous trig-free deterministic animation/hash math; ash shaping is algebraic.
- Puddle reflection descriptors are reused from a bounded pool.

## Deep audit of unchanged systems

The all-weather qualification independently exercises the locked 3D snow path, fog ownership, water hot path, remote tornado culling, world lightning, RAVE show/lasers, battle weather persistence, cloud-bank pitch/persistence/coherence, celestial zenith/stress, rain walk/ledge/map-edge/rendered-world continuity, sand pitch behavior, leaves, host compatibility, general performance invariants and 3D pipeline integrity. Existing cloud compact instancing/cached puff data and other passing bounded/cached systems are retained rather than rewritten.

## Source qualification

- New all-weather performance ownership regression: **12/12 PASS**.
- Exact 8.2.5 negative control: **10/12 new checks FAIL**, as required.
- Sequential all-weather subsystem qualification: **25/25 programs PASS**.
- Maintained developer sweep: **124/124 programs PASS**.

## Candidate package replay

The versioned candidate ZIP was extracted into a clean directory and replayed through the same wall:

- All-weather performance ownership: **12/12 PASS**.
- Sequential all-weather subsystem qualification: **25/25 programs PASS**.
- Maintained developer sweep: **124/124 programs PASS**.
- `test_mod.py --lua`: **198 passed, 0 failed, 0 skipped**.
- Revision gate: **80/80 PASS**.
- Runtime Lua compile: **129/129 PASS**.

The final archive is rebuilt with this audit and qualification included and replayed once more. Final archive identity and exact-byte results are published in the external validation record.

## Truth boundary

This environment can execute source/runtime/package regressions and instrumented code-path tests but cannot run a fresh interactive Gen1Recomp session on the user's exact low-powered phone or 16 GB desktop GPU. This release therefore claims verified architectural workload reduction and exact-package behavior, not fabricated device FPS numbers.
