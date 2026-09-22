#!/usr/bin/env python3
"""
Decode in-game DEBUG HUD fragments an AI receives from the user.
Example:
  python3 tools/runtime_hints.py "wx:3d | v3:full-atmos:DRAMALESS_SHAPE"
  python3 tools/runtime_hints.py --v3 "retrying: voxel-pipeline-not-ready"
"""
from __future__ import annotations
import argparse, re, json

def decode_wx(s: str) -> str:
    s = (s or "").lower()
    if "2d" in s: return "Player forced original Weather FX 2D overlays. 3D draws must not suppress rain/fog."
    if "3d" in s: return "Player forced 3D path when host available."
    if "auto" in s: return "AUTO: 3D if host+bridge active, else 2D."
    return "Unknown wx mode."

def decode_v3(s: str) -> list[str]:
    s = s or ""
    tips = []
    if not s or s in ("off", "bridge-unavailable"):
        tips.append("3D bridge inactive — stock 2D path only.")
    if "no-dramaless" in s or "no-voxel" in s:
        tips.append("Host mod not found. Need one of: DRAMATIC_SHAPE, DRAMALESS_SHAPE, potato_voxel, STADIUM2_OVERWORLD_MODELS.")
    if "missing-exports" in s:
        tips.append("Host lacks exports.lib — cannot require Voxel3D.")
    if "CinematicAtmos-load-failed" in s:
        tips.append("CinematicAtmos failed to load — check stubs and host DayNight/ShadowMap/Sky.")
    if "full-atmos" in s:
        tips.append("Install path succeeded. If nothing visible, check outdoor+rain and |err: suffix.")
    if "|err:" in s:
        err = s.split("|err:", 1)[-1]
        tips.append(f"Last draw error: {err}")
        tips.append("Inspect CinematicAtmos.draw / beginEffect polyfill / shader compile.")
    if "2d-fallback" in s:
        tips.append("Host detected but 3D not active — fallback overlays should show.")
    if "retrying" in s or "waiting" in s:
        tips.append("Bridge still waiting for host/pipeline — load order issue.")
    if not tips:
        tips.append(f"Unrecognized v3 status: {s!r}")
    return tips

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("blob", nargs="?", default="", help="raw HUD snippet")
    ap.add_argument("--wx", default="")
    ap.add_argument("--v3", default="")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    blob = args.blob
    wx = args.wx
    v3 = args.v3
    m = re.search(r"wx:([^\s|]+)", blob)
    if m and not wx: wx = m.group(1)
    m = re.search(r"v3:([^\n]+)", blob)
    if m and not v3: v3 = m.group(1).strip()
    out = {
        "wx": wx,
        "wx_meaning": decode_wx(wx),
        "v3": v3,
        "v3_tips": decode_v3(v3),
    }
    if args.json:
        print(json.dumps(out, indent=2))
    else:
        print("wx:", out["wx"], "->", out["wx_meaning"])
        print("v3:", out["v3"])
        for t in out["v3_tips"]:
            print("  -", t)

if __name__ == "__main__":
    main()
