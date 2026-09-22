#!/usr/bin/env python3
"""Compatibility audit: markers for known host/companion mods."""
from __future__ import annotations
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]

MARKERS = {
    "Dramaless / Potato voxel": [
        ("lib/DramalessAtmos.lua", "HOSTS"),
        ("lib/VoxelAtmosBridge.lua", "Voxel"),
        ("lib/Settings.lua", "present"),
    ],
    "Gen2 3D sprites": [
        ("lib/DramalessAtmos.lua", "gen2"),
        ("lib/VoxelAtmosBridge.lua", "gen2"),
    ],
    "Crystal 251": [
        ("lib/Battle.lua", "crystal"),
        ("lib/Battle.lua", "CRYSTAL"),
        ("main.lua", "CRYSTAL_251"),
    ],
    "Gen3 battle UI": [
        ("lib/BattleDraw.lua", "gen3"),
        ("lib/BattleField.lua", "gen3"),
        ("lib/BattleDraw.lua", "overlay"),
    ],
    "UI mods (non-destructive)": [
        ("lib/Settings.lua", "Own schema only"),
        ("main.lua", "register"),
    ],
    "Indoor / caves": [
        ("lib/WeatherState.lua", "_indoorAccum"),
        ("lib/Scene.lua", "indoorMaps"),
    ],
}

def main():
    print("=== COMPATIBILITY MATRIX ===\n")
    for name, checks in MARKERS.items():
        hits = []
        for rel, needle in checks:
            t = (ROOT / rel).read_text(errors="ignore") if (ROOT / rel).exists() else ""
            hits.append(needle.lower() in t.lower())
        status = "OK" if any(hits) else "WEAK"
        if all(hits):
            status = "STRONG"
        print(f"{status:6}  {name}")
        for (rel, needle), h in zip(checks, hits):
            print(f"         {'✓' if h else '·'} {rel} ~ {needle}")
        print()
    return 0

if __name__ == "__main__":
    sys.exit(main())
