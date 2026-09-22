#!/usr/bin/env python3
"""
Post-edit contract checker for Weather FX.
Run after AI edits to ensure presentation/3D/2D contracts still hold.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="replace")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    fails = []
    warns = []

    contracts = [
        ("lib/Settings.lua", r'key\s*=\s*"present"', "WX PRESENT setting must exist"),
        ("lib/Settings.lua", r'function Settings\.force2dPresent', "force2dPresent helper"),
        ("lib/Settings.lua", r'function Settings\.allow3dPresent', "allow3dPresent helper"),
        ("lib/Draw.lua", r"use3dPrecip", "2D precip suppress helper"),
        ("lib/Draw.lua", r"force2dPresent", "Draw must honor 2D present mode"),
        ("lib/DramalessAtmos.lua", r"beginEffect", "beginEffect polyfill required for Dramaless"),
        ("lib/DramalessAtmos.lua", r"endScene", "endScene wrap required"),
        ("lib/DramalessAtmos.lua", r"want3d", "3D gate must respect WX PRESENT"),
        ("lib/VoxelAtmosBridge.lua", r"DramalessAtmos", "bridge routes to DramalessAtmos"),
        ("main.lua", r"VoxelAtmos", "main wires VoxelAtmos"),
        ("main.lua", r"syncFromWeatherFx", "main syncs weather into 3D backend"),
        ("lib/voxel_atmos/stubs/ForestAtmos.lua", r"ForestAtmos", "ForestAtmos stub present"),
    ]
    for rel, pat, msg in contracts:
        p = ROOT / rel
        if not p.is_file():
            fails.append({"code": "missing_file", "msg": f"{rel} missing ({msg})"})
            continue
        if not re.search(pat, read(rel)):
            fails.append({"code": "contract", "msg": f"{rel}: {msg} ({pat})"})

    # CinematicAtmos must remain loadable path
    if not (ROOT / "lib/voxel_atmos/CinematicAtmos.lua").is_file():
        fails.append({"code": "missing_file", "msg": "CinematicAtmos.lua missing"})

    # 2D path must still exist
    for rel in ("lib/Fog.lua", "lib/Particles.lua"):
        if not (ROOT / rel).is_file():
            fails.append({"code": "missing_file", "msg": f"{rel} missing — 2D weather broken"})

    report = {
        "ok": len(fails) == 0,
        "fails": fails,
        "warns": warns,
        "hint": "Re-run ai_debug.py after fixing contracts.",
    }
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print("edit_guard:", "PASS" if report["ok"] else "FAIL")
        for f in fails:
            print(f"  FAIL {f['code']}: {f['msg']}")
        for w in warns:
            print(f"  WARN {w}")
    return 0 if report["ok"] else 1

if __name__ == "__main__":
    sys.exit(main())
