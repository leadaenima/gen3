# Weather FX tools

Run after **every revision** before shipping a zip.

## Required gate

```bash
cd weather_fx
python3 tools/revision_gate.py   # must exit 0
python3 tools/run_all.py --lua   # full static/compat audit + maintained Lua suites when available
```

| Tool | Role |
|------|------|
| **revision_gate.py** | Core release contracts, labels, battle toggles, Gen1/Gen2 scene dispatch, config support |
| **test_mod.py** | Structure + 3D bridge contracts; `--lua` runs maintained headless release suites |
| **test_night_sky.py** | Star field / celestial contracts |
| **test_scope_hygiene.py** | Forward refs, globals, and forbidden boot-time `src.*` captures |
| **test_love_sandbox.py** | No blocked `love` APIs anywhere in shipped Lua |
| **audit_full.py --strict** | Architectural/product audit; HIGH findings fail the gate |
| **compat_aggressive.py / audit_compat.py** | Companion/host compatibility risk checks |
| **edit_guard.py** | Post-edit contract checks |
| **run_all.py** | Runs the release gate, maintained tests, full audit, compatibility audits and diagnostics |
| ai_debug.py / mod_map.py | Diagnostics |

## AI / human workflow

1. Edit only Weather FX (unless the user says otherwise).
2. `python3 tools/revision_gate.py` — fix until exit 0.
3. `python3 tools/run_all.py --lua` — full pass where a Lua interpreter exists.
4. Run the engine harness on Gen 1 and Gen 2 when the engine checkout is available.
5. Zip + CHANGELOG version bump.

User-confirmed stable baseline is **4.33.7**. The `BASELINE` / `BASELINE.md` files in a working revision identify its immediate parent package and scope.

## 8.1.18 frozen-baseline regression wall

`python3 tools/run_8118_regression_wall.py` runs the fast dedicated wall added after 8.1.17 was approved as the gameplay baseline. It verifies byte-identical runtime/assets, manifest behavior, semantic snapshots, config/quality defaults, exhaustive weather, celestial/wind/BuildingLight stress, 1,000-night celestial-event scheduling, Weather-OFF ownership and package wiring. The full `run_all.py --lua` also includes these gates.
