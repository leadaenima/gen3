#!/usr/bin/env python3
"""Emit a compact architecture map of Weather FX for AI context."""
from __future__ import annotations
import argparse, json, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ROLES = {
    "main.lua": "entry: pipelines, update/draw, VoxelAtmos wiring",
    "lib/WeatherState.lua": "weather state machine AUTO/CYCLE/PIN",
    "lib/Types.lua": "weather catalogue and ids",
    "lib/Draw.lua": "2D overlays; respects 3D suppress",
    "lib/Settings.lua": "mod options including WX PRESENT",
    "lib/Battle.lua": "battle weather rules",
    "lib/VoxelAtmosBridge.lua": "routes optional 3D backend",
    "lib/DramalessAtmos.lua": "Dramaless/Potato 3D atmosphere host",
    "lib/voxel_atmos/CinematicAtmos.lua": "Kanto-style 3D atmos draw",
    "lib/Fog.lua": "2D fog",
    "lib/Particles.lua": "2D precipitation particles",
}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    files = []
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        if any(x in rel for x in (".git", "__pycache__", ".zip")):
            continue
        files.append({
            "path": rel,
            "bytes": p.stat().st_size,
            "role": ROLES.get(rel, ""),
        })
    report = {
        "mod": "weather_fx",
        "root": str(ROOT),
        "file_count": len(files),
        "files": files,
        "edit_hotspots": [
            "lib/DramalessAtmos.lua",
            "lib/VoxelAtmosBridge.lua",
            "lib/Draw.lua",
            "lib/Settings.lua",
            "main.lua",
            "lib/voxel_atmos/CinematicAtmos.lua",
        ],
        "do_not_edit_other_mods": True,
    }
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"Weather FX map — {len(files)} files")
        print("HOTSPOTS:")
        for h in report["edit_hotspots"]:
            print(f"  {h} — {ROLES.get(h, '')}")
        print("ALL:")
        for f in files:
            role = f"  # {f['role']}" if f["role"] else ""
            print(f"  {f['path']} ({f['bytes']}){role}")

if __name__ == "__main__":
    main()
