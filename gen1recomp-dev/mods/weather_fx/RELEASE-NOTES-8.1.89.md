# Weather FX 8.1.89 — Continuous 2D Weather / No Restart Loop

Built directly from exact Weather FX 8.1.88.

## Fixed: 2D weather periodically restarting

Some hosts rebroadcast persisted `mod.options_changed` values during save/menu-cache refresh. Weather FX 8.1.88 treated every repeated WEATHER event as a fresh player edit and pushed the same render-pipeline rung again. On hosts where `Pipelines.setLevel()` rebuilds or invalidates the stage, classic 2D rain/snow visibly restarted from frame zero every few seconds.

8.1.89 makes the WEATHER synchronization path idempotent:

- an unchanged canonical WEATHER event is a strict no-op;
- an already-active requested pipeline rung is read-only and is not sent through `setLevel()` again;
- pending reconciliation also exits immediately when the engine already reports the requested rung;
- a genuine player WEATHER change still applies immediately exactly once.

The 8.1.88 final-frame 2D compositor fix and Options/Mod Manager synchronization remain unchanged, as do all Terrarium-inspired weather-world interactions.

## Qualification

- New restart regression: **5/5 PASS** on 8.1.89.
- Exact 8.1.88 negative control: **1/5 PASS, 4/5 FAIL**.
- Maintained Lua developer sweep: **84/84 programs PASS**.
- Settings runtime: **735/735 PASS**.
- Render pipeline: **354/354 PASS**.
- 2D weather styling: **94/94 PASS**.
- Dual weather selector: **15/15 PASS**.
- 2D/options synchronization: **4/4 PASS**.
- Structural `test_mod` (non-Lua wrapper): **129 passed / 0 failed / 1 skipped** (Lua separately proven above).
- Voxel-host compatibility: **27/27 PASS**.
- Love sandbox scan: **128 runtime Lua files PASS**.

No fresh live-game framebuffer/device session was captured for 8.1.89; this release is qualified by executable regression, structural, compatibility and package evidence and does not claim manual visual playtesting.
