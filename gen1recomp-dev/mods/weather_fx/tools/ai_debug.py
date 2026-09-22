#!/usr/bin/env python3
"""
Weather FX — AI debug tool

Headless structural + integration checker for the Weather FX mod.
Produces a machine-readable report an AI (or human) can use to locate
failures without running the full LÖVE engine.

Usage (from mod root or any cwd):
  python3 tools/ai_debug.py
  python3 tools/ai_debug.py --json
  python3 tools/ai_debug.py --out tools/last_ai_report.txt

Exit codes:
  0 = no FAIL findings
  1 = one or more FAIL findings
  2 = tool could not run (missing paths)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def mod_root() -> Path:
    here = Path(__file__).resolve().parent
    return here.parent


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")


def balance_ok(src: str) -> list[str]:
    issues = []
    for a, b in (("(", ")"), ("{", "}"), ("[", "]")):
        if src.count(a) != src.count(b):
            issues.append(f"unbalanced {a}{b}: {src.count(a)} vs {src.count(b)}")
    return issues


def main() -> int:
    ap = argparse.ArgumentParser(description="Weather FX AI debug tool")
    ap.add_argument("--json", action="store_true", help="Emit JSON report")
    ap.add_argument("--out", type=str, default="", help="Also write report to path")
    args = ap.parse_args()

    root = mod_root()
    findings: list[dict] = []

    def add(level: str, code: str, msg: str, path: str = ""):
        findings.append({"level": level, "code": code, "msg": msg, "path": path})

    # --- manifest ---
    man_path = root / "manifest.json"
    version = "?"
    if not man_path.is_file():
        add("FAIL", "manifest.missing", "manifest.json not found", str(man_path))
    else:
        try:
            man = json.loads(read(man_path))
            version = str(man.get("version", "?"))
            if man.get("entry") != "main.lua":
                add("WARN", "manifest.entry", f"entry is {man.get('entry')!r}, expected main.lua")
            if "present" not in read(root / "lib" / "Settings.lua"):
                add("FAIL", "settings.present", "WX PRESENT option missing from Settings.lua")
        except Exception as e:
            add("FAIL", "manifest.parse", str(e), str(man_path))

    # --- required files ---
    required = [
        "main.lua",
        "lib/Draw.lua",
        "lib/Settings.lua",
        "lib/WeatherState.lua",
        "lib/Types.lua",
        "lib/VoxelAtmosBridge.lua",
        "lib/DramalessAtmos.lua",
        "lib/voxel_atmos/CinematicAtmos.lua",
        "lib/voxel_atmos/DistantWorld.lua",
        "lib/voxel_atmos/HorizonApron.lua",
        "lib/voxel_atmos/WeatherSetting.lua",
        "lib/voxel_atmos/stubs/ForestAtmos.lua",
        "lib/voxel_atmos/stubs/Mat4.lua",
        "lib/voxel_atmos/stubs/TileShape.lua",
        "lib/voxel_atmos/stubs/SpriteBillboards.lua",
        "lib/voxel_atmos/stubs/TerrainAtlas.lua",
    ]
    for rel in required:
        p = root / rel
        if not p.is_file():
            add("FAIL", "file.missing", f"required file missing: {rel}", rel)
        else:
            issues = balance_ok(read(p))
            for iss in issues:
                add("WARN", "syntax.balance", f"{rel}: {iss}", rel)

    # --- symbol probes ---
    probes = {
        "lib/DramalessAtmos.lua": [
            "beginEffect",
            "endEffect",
            "CinematicAtmos",
            "want3d",
            "endScene",
            "handlesPrecipitation",
            "HOSTS",
        ],
        "lib/VoxelAtmosBridge.lua": [
            "DramalessAtmos",
            "handlesPrecipitation",
            "syncFromWeatherFx",
        ],
        "lib/Draw.lua": [
            "use3dPrecip",
            "use3dFog",
            "force2dPresent",
            "VoxelAtmos",
        ],
        "lib/Settings.lua": [
            'key = "present"',
            "force2dPresent",
            "allow3dPresent",
            "presentMode",
        ],
        "main.lua": [
            "VoxelAtmos",
            "syncFromWeatherFx",
        ],
    }
    for rel, needles in probes.items():
        p = root / rel
        if not p.is_file():
            continue
        src = read(p)
        for n in needles:
            if n not in src:
                add("FAIL", "symbol.missing", f"{rel} missing {n!r}", rel)

    # --- CinematicAtmos dependency map ---
    ca = root / "lib/voxel_atmos/CinematicAtmos.lua"
    if ca.is_file():
        reqs = sorted(set(re.findall(r'V\.require\("([^"]+)"\)', read(ca))))
        host_or_stub = {
            "DayNight": "host",
            "ShadowMap": "host",
            "Sky": "host",
            "Voxel3D": "host",
            "ForestAtmos": "stub",
            "Mat4": "stub_or_host",
            "TileShape": "stub",
            "SpriteBillboards": "stub",
            "TerrainAtlas": "stub",
            "WeatherSetting": "own",
        }
        for r in reqs:
            kind = host_or_stub.get(r, "unknown")
            if kind == "stub":
                stub = root / "lib/voxel_atmos/stubs" / f"{r}.lua"
                if not stub.is_file():
                    add("FAIL", "stub.missing", f"CinematicAtmos needs stub for {r}", str(stub))
            elif kind == "own":
                own = root / "lib/voxel_atmos" / f"{r}.lua"
                if not own.is_file():
                    add("FAIL", "own.missing", f"CinematicAtmos needs {r}.lua", str(own))
            elif kind == "unknown":
                # Weather FX's V.require resolves its own top-level lib first,
                # then the voxel-atmos sibling set. Recognise those concrete
                # files before reporting a host dependency as unresolved.
                own_top = root / "lib" / f"{r}.lua"
                own_voxel = root / "lib/voxel_atmos" / f"{r}.lua"
                if not own_top.is_file() and not own_voxel.is_file():
                    add("WARN", "dep.unknown", f"CinematicAtmos requires {r} with no resolver plan")

        if "beginEffect" not in read(root / "lib/DramalessAtmos.lua"):
            add("FAIL", "polyfill.beginEffect", "DramalessAtmos must polyfill Voxel3D.beginEffect")

    # --- presentation mode contract ---
    settings = root / "lib/Settings.lua"
    if settings.is_file():
        s = read(settings)
        for choice in ('"auto"', '"2d"', '"3d"'):
            if choice not in s:
                add("FAIL", "present.choice", f"Settings missing present choice {choice}")

    # --- summary ---
    counts = {"FAIL": 0, "WARN": 0, "INFO": 0}
    for f in findings:
        counts[f["level"]] = counts.get(f["level"], 0) + 1

    report = {
        "mod": "weather_fx",
        "version": version,
        "root": str(root),
        "counts": counts,
        "findings": findings,
        "guidance": [
            "In-game: enable DEBUG HUD; read wx: (2d|3d|auto) and v3: bridge status.",
            "WX PRESENT=2d must restore original Weather FX overlays.",
            "3D path must work on ALL hosts: DRAMATIC_SHAPE, DRAMALESS_SHAPE, potato_voxel, STADIUM2_OVERWORLD_MODELS.",
            "If v3 contains |err:, that string is the last CinematicAtmos.draw error.",
            "Dramaless lacks Voxel3D.beginEffect; Weather FX polyfills it in memory.",
            "Battles always use Weather FX 2D/battle path regardless of WX PRESENT.",
        ],
        "in_game_checklist": [
            "Install Dramatic Shape, Dramaless, or Potato Voxel, enable VOXEL camera",
            "Set WX PRESENT to 3D, force rain, go outdoors",
            "Note DEBUG HUD v3: and wx: lines",
            "Set WX PRESENT to 2D — original fog/rain should return",
        ],
    }

    if args.json:
        text = json.dumps(report, indent=2)
    else:
        lines = [
            f"Weather FX AI debug report",
            f"version: {version}",
            f"root: {root}",
            f"counts: FAIL={counts.get('FAIL',0)} WARN={counts.get('WARN',0)}",
            "",
            "FINDINGS:",
        ]
        if not findings:
            lines.append("  (none)")
        for f in findings:
            loc = f" [{f['path']}]" if f.get("path") else ""
            lines.append(f"  {f['level']} {f['code']}: {f['msg']}{loc}")
        lines.append("")
        lines.append("GUIDANCE:")
        for g in report["guidance"]:
            lines.append(f"  - {g}")
        lines.append("")
        lines.append("IN-GAME CHECKLIST:")
        for g in report["in_game_checklist"]:
            lines.append(f"  - {g}")
        text = "\n".join(lines) + "\n"

    sys.stdout.write(text)
    if args.out:
        outp = Path(args.out)
        if not outp.is_absolute():
            outp = root / outp
        outp.parent.mkdir(parents=True, exist_ok=True)
        outp.write_text(text, encoding="utf-8")

    return 1 if counts.get("FAIL", 0) else 0


if __name__ == "__main__":
    sys.exit(main())
