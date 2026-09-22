# Weather FX 8.2.4 Final Audit

## Scope

8.2.4 is built directly from exact Weather FX 8.2.3 after the user reported that every weather containing 3D snow remained unplayably slow, including with SNOW ACCUMULATION OFF. Unlike the prior renderer-only passes, this release audits the complete `WorldPrecip` snow ownership/update/support path under both successful and failed procedural-GPU conditions.

## Root causes proven by the full-path audit

Two hidden costs survived 8.2.3:

1. **Accumulation OFF did not actually retire SnowPack support work.** Pure 3D snowfall still constructed support context, exact-resolved invisible CPU snow probes against terrain, advanced SnowPack, and ran the rain-interaction update path every frame.
2. **A procedural-GPU failure could restore the complete logical storm to CPU simulation.** Before a procedural draw was proven, or when the backend was unavailable, the compatibility path initialized CPU snow from the full logical population. That could mean up to 100,000 SNOW or 200,000 BLIZZARD flakes being CPU-integrated and rebuilt into legacy visible geometry.

These are architectural path findings, not inferred shader guesses.

## Repairs

- Pure 3D snow with accumulation OFF now performs **zero SnowPack context builds, zero exact terrain sweeps, zero SnowPack updates, zero ground/foot staging**, and skips the rain-only `WorldInteractionPrecip` update when no retained rain beads exist.
- Proven procedural GPU snow retains one third-person CPU telemetry/lifecycle identity. First-person keeps a bounded face-contact sample capped at 16. Ground accumulation coverage is handled by aggregate deposition rather than exact-resolving the procedural visual population flake by flake.
- With accumulation ON, pure-snow support context is reused for 100 ms and refreshed immediately on map change or meaningful movement. Ground-bank and footprint staging share the same slow-state refresh. Falling visual snow continues to move every rendered frame.
- If procedural GPU snow is unavailable or fails proof, the legacy CPU-visible renderer is hard-capped by the established per-quality CPU budgets: **POTATO 360 / LOW 720 / MEDIUM 1,640 / HIGH 3,200 / MAX 4,800**. It can no longer inherit the full 100k/200k logical storm.
- Exact terrain sweeps on that compatibility path are independently bounded by `snowProbeCap` rather than by the visible CPU fallback population.

## Measured executable work-count comparison

The same instrumented 600-frame `WorldPrecip.update` workload was run against exact 8.2.3 and the 8.2.4 source tree across SNOW and BLIZZARD at POTATO/LOW/MEDIUM/HIGH/MAX.

### Accumulation OFF — ten 600-frame cases

- Exact 8.2.3: **6,000** SnowPack context builds, **310,984** exact flake support sweeps, **6,000** SnowPack updates.
- 8.2.4: **0** SnowPack context builds, **0** exact flake support sweeps, **0** SnowPack updates.

At the MAX BLIZZARD 600-frame case specifically, exact 8.2.3 performed 600 support-context builds + 57,600 exact sweeps + 600 SnowPack updates. 8.2.4 performs 0 + 0 + 0 while keeping the same 200,000 logical procedural snow population.

### Accumulation ON — ten 600-frame cases

- Exact 8.2.3: **6,000** support-context builds, **312,000** exact flake support sweeps, **6,000** SnowPack updates, **916** ground stages, **6,000** footprint stages.
- 8.2.4: **916** support-context builds, **0** procedural exact flake support sweeps, **6,000** SnowPack updates, **916** ground stages, **916** footprint stages.

The retained 6,000 SnowPack updates are the intentional accumulation/melt state integration; expensive support/ground/foot staging is the slow-state work. These figures are instrumented code-path counts, not claimed phone FPS.

## Preservation

8.2.4 preserves the complete 8.2.3 visible renderer contract on a proven GPU backend: far-point/near-crystal LOD, smooth per-render-frame motion, live render distance, continuous no-moving-emitter/no-whole-field-handoff behavior, and the authored logical 100,000 SNOW / 200,000 MAX BLIZZARD ceilings. RAVE, cloud-bank zenith, sun/moon, battle presentation, rain and other weather behavior remain unchanged.

## Source qualification

- 8.2.4 exhaustive full 3D snow path audit: **7/7 PASS**.
- Maintained developer sweep: **122/122 programs PASS**.
- `test_mod.py --lua`: **198 passed, 0 failed, 0 skipped**.
- Revision gate: **80/80 PASS**.
- Runtime Lua compile: **129/129 PASS**.
- Exact 8.2.3 negative control: **6/7 new full-path checks FAIL**, as required.

## Candidate package replay

The versioned 8.2.4 candidate ZIP was extracted and replayed before final audit documents were embedded:

- Full 3D snow path audit: **7/7 PASS**.
- Maintained developer sweep: **122/122 programs PASS**.
- `test_mod.py --lua`: **198 passed, 0 failed, 0 skipped**.
- Revision gate: **80/80 PASS**.
- Runtime Lua compile: **129/129 PASS**.

The final ZIP is rebuilt with this audit and qualification included, then replayed again. Final archive identity and exact-package results are published in the external validation record.

## Truth boundary

This environment cannot run a fresh interactive Gen1Recomp session on the user's exact low-powered phone or 16 GB desktop GPU. 8.2.4 therefore claims measured executable work-count reductions, bounded fallback behavior, regression results and exact-package replay — not a fabricated device FPS number.
