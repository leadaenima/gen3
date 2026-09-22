# Weather FX 8.1.89 — Final Qualification

Built directly from exact Weather FX 8.1.88.

## Release blocker fixed

Classic 2D weather no longer periodically restarts when the host rebroadcasts the same WEATHER option. Unchanged WEATHER authority is now idempotent and an already-live pipeline rung is never redundantly reapplied. Real player changes remain immediate.

## Qualification

- New restart regression: 5/5 PASS.
- Exact 8.1.88 negative control: 1/5 PASS, 4/5 FAIL.
- Maintained Lua developer sweep: 84/84 programs PASS.
- Settings runtime: 735/735 PASS.
- Render pipeline: 354/354 PASS.
- 2D weather styling: 94/94 PASS.
- Dual selector: 15/15 PASS.
- 2D/options sync: 4/4 PASS.
- `test_mod` structural gate: 129 passed / 0 failed / 1 skipped.
- Voxel-host compatibility: 27/27 PASS.
- Love sandbox: 128 runtime Lua files PASS.

No fresh live-game framebuffer/device session was captured; qualification is executable/runtime/package evidence, not a claim of manual visual playtesting.
