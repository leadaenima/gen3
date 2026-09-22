# Weather FX 8.1.91 Final Audit

Parent: exact Weather FX 8.1.90 package/source checkpoint (`7b9e15cdfd1a66604e99414141372af1e38e81e415cf734b1636079d67937f9b`).

## Intended runtime delta

- `lib/voxel_atmos/CinematicAtmos.lua`
  - Replaces partial intensity fading of duplicate distant snow/blizzard precipitation with an exclusive local-snow ownership handoff above the existing live-noise threshold.
- `lib/DramalessAtmos.lua`
  - Stops using `_trainSource` as the Battle Art/Voxel Nexus discriminator; current public Battle Art exports that helper too.
  - Detects Voxel Nexus from the additional `realisticWorld.WaterEngine.tideOffset` seam.
- `lib/voxel_atmos/ConnectedWater3D.lua`
  - Tracks `host` vs `weather-fx` relief ownership and invalidates the host Water shader exactly when that mode changes, after forcing host `WAVE_HEIGHT=0` during Weather FX physical ownership.

No Battle Art, Voxel Nexus, engine, ROM, or other companion-mod file is edited.

## Focused regression results

- 8.1.90 inherited snow-fountain guard: 9/9 PASS.
- 8.1.91 light/local snow ownership guard: 6/6 PASS.
- Public Battle Art water guard: 12/12 PASS.
- Voxel Nexus water guard: 16/16 PASS.
- 8.1.91 current Battle Art compatibility guard: 5/5 PASS.
- 8.1.91 developer sweep: 101/101 programs PASS.
- Runtime Lua syntax compile: 128/128 PASS.
- `tools/edit_guard.py`: PASS.

## Negative controls

- Reinstating the exact 8.1.90 snow fade makes the new snow guard fail 3/6.
- Reinstating the 8.1.90 `_trainSource` lineage rule and removing relief-mode shader invalidation makes the new Battle Art water guard fail 3/5.

## Full historical runner note

`tools/run_all.py --lua` remains nonzero because it chains historical exact-version freeze/package checks and known stale legacy assertions that intentionally cannot pass on a later release (for example old manifest/runtime freezes and a legacy settings-menu assertion). The current 8.1.91 maintained developer sweep, current revision gate, feature audit, host-compatibility checks, sandbox checks, and `test_mod.py --lua` all pass.

## Visual status

The supplied screenshots are consistent with the two code paths corrected here. No fresh live Battle Art framebuffer/device session was available in this environment. Final eyes-on confirmation therefore remains required on the user's Battle Art installation: snow must be spatially distributed without a dense point-source column, and Weather FX water must present one physical relief surface without Battle Art's separately compiled relief pattern leaking through.
