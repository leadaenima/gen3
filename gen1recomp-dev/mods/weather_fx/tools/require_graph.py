#!/usr/bin/env python3
"""Approximate V.require / require graph for Weather FX Lua modules."""
from __future__ import annotations
import argparse, json, re
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
REQ = re.compile(r'(?:V\.require|require)\(\s*["\']([^"\']+)["\']\s*\)')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--module", default="", help="filter edges involving this name")
    args = ap.parse_args()
    edges = []
    for p in ROOT.rglob("*.lua"):
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        src = p.read_text(encoding="utf-8", errors="replace")
        for m in REQ.finditer(src):
            edges.append({"from": rel, "to": m.group(1)})
    if args.module:
        edges = [e for e in edges if args.module in e["from"] or args.module in e["to"]]
    if args.json:
        print(json.dumps({"edges": edges, "count": len(edges)}, indent=2))
    else:
        print(f"{len(edges)} require edges")
        for e in edges[:100]:
            print(f"  {e['from']} -> {e['to']}")
        if len(edges) > 100:
            print(f"  ... {len(edges)-100} more")

if __name__ == "__main__":
    main()
