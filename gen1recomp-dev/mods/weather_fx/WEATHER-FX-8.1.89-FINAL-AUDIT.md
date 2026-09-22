# Weather FX 8.1.89 — Final Audit

Built directly from exact Weather FX 8.1.88.

## Runtime delta

Exactly one runtime Lua file changes from 8.1.88: `lib/Settings.lua`.

The change removes same-value WEATHER reapplication:
- duplicate canonical WEATHER events return without revision/pipeline churn;
- a stable observed pipeline rung is never sent through `setLevel()` again;
- pending reconciliation is also idempotent when the requested rung is already live.

This directly addresses the reported pattern where 2D weather started correctly, then restarted from the beginning every few seconds.

## Regression evidence

- `weather_2d_restart_8189_test.lua`: 5/5 PASS on 8.1.89.
- Exact 8.1.88 negative control: 1/5 PASS, 4/5 FAIL.
- Existing 2D/options synchronization: 4/4 PASS.
- Dual weather selector: 15/15 PASS.
- Settings runtime: 735/735 PASS.
- 2D styling: 94/94 PASS.
- Render pipeline: 354/354 PASS.
- Maintained Lua developer sweep: 84/84 programs PASS.
- `test_mod` structural wrapper: 129 passed / 0 failed / 1 skipped; its Lua wall was executed separately in the 84/84 developer sweep.
- Voxel-host compatibility: 27/27 PASS.
- Love sandbox: 128 shipped runtime Lua files scanned PASS.

The monolithic aggregate wrappers and `feature_audit.py` exceeded this environment's single-command execution window on attempted runs; those timeouts are not counted as passes. Release qualification instead uses the completed bounded maintained sweep plus direct structural/compatibility gates above.

No fresh live-game framebuffer/device session was captured.
