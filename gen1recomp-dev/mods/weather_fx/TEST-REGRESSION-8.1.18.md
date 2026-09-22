# Weather FX 8.1.18 — Frozen 8.1.17 Regression Wall

## Purpose

8.1.18 is deliberately a **test-only hardening release**. The user-approved Weather FX 8.1.17 gameplay/render runtime is the baseline. No executable Weather FX Lua, compatibility runtime, or shipped visual/audio asset is intentionally changed in 8.1.18.

## New permanent regression layers

1. **Byte-for-byte runtime freeze** — 154 executable/compat/asset files are pinned by SHA-256 and size to the approved 8.1.17 package. This catches even a one-byte accidental runtime edit.
2. **Manifest behavior freeze** — host support, permissions, dependencies, priority, category and other behavior-relevant manifest fields are pinned; only release-version/baseline-note metadata may differ.
3. **Semantic runtime snapshot** — 791 deterministic observations execute the 8.1.17 weather catalogue, celestial simulation, lunar/horizon functions, wind profiles/evolution and BuildingLight falloff and compare exact output.
4. **Config/quality snapshot** — 304 defaults and quality-budget observations are frozen.
5. **Exhaustive weather catalogue** — 1,407 assertions sweep all 29 weather definitions, channels, follows edges, scheduling fields, battle/chip metadata, precipitation families and lightning authority.
6. **Celestial stress** — 49,836 assertions sweep seasons, 15-minute day/night samples, sun/moon vectors, horizon fractions, twilight, star visibility, eclipses and two lunar cycles.
7. **Wind stress** — 282,245 assertions run every weather through deterministic multi-dt wind evolution, including hitch-sized dt values, vector consistency, bounded advection, audio/pitch bounds and seeded repeatability.
8. **Building-light stress** — 411 assertions sweep every integer distance from 0–64 cells, monotonic light-pollution response, clamping and gradual approach/retreat smoothing.
9. **Night-event stress** — 482,001 assertions simulate 1,000 full nights. Every night must produce exactly four ordinary single shooting-star events; meteor shower eligibility remains one 10% roll per night and at most one shower. The pinned seed produced 104 shower nights / 1,000.
10. **Weather-OFF cross-module contract** — 15 checks lock the distinct OFF/AUTO/CYCLE ladder and the WeatherState/audio/3D/tornado hard-disable chain while keeping the celestial sky independent.
11. **Package/test-surface guard** — verifies the new tests are actually wired into `run_all.py`, runtime modules are frozen, and junk/cache files are not shipped.

The new wall contributes **817,213 explicit checks/observations** before counting the pre-existing Weather FX suite.

## Mutation proof

The tests were deliberately broken before release:

- Appending one harmless comment to `main.lua` caused the runtime byte-freeze test to fail.
- Changing approved normal-rain density from `0.90` to `0.91` caused both the semantic snapshot and exhaustive weather-catalogue test to fail.
- Both mutations were restored from exact backups, after which the affected tests returned green and the 154-file runtime hash freeze passed again.

This proves the new baseline tests are not decorative.

## Existing-suite preservation

Verified after adding the tests:

- `tools/edit_guard.py`: PASS
- `tools/test_mod.py --lua`: **181 passed / 0 failed / 0 skipped**
- Lua syntax: **217/217** files PASS
- 8.1.17 constellation midpoint: **6/6**
- 8.1.16 celestial quality: **33/33**
- 8.1.15 celestial optics: **32/32**
- 8.1.14 night/tornado contract: **15/15**
- 3D pipeline integrity: **117/117**
- current voxel-host contract: **26/26**
- aggressive compatibility: **0 HIGH** findings
- strict full audit: **0 HIGH**, 3 MED live-engine-only checks

`tools/run_all.py --lua` now includes the entire new regression wall. In this container the all-in-one wrapper exceeds the command time window because the combined old + new suite is intentionally very large; its constituent release-critical gates above were run directly. This is a duration boundary, not a reported assertion failure.

## Runtime boundary

Tests cannot see the final Gen1Recomp/LÖVE framebuffer. 8.1.18 intentionally does not alter runtime behavior, and the byte/semantic freezes prove the package's executable behavior source remains 8.1.17. Live visual checks are still the final proof of pixels on each host/GPU.
