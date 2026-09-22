#!/usr/bin/env python3
"""Search symbols / patterns across Weather FX Lua for AI navigation."""
from __future__ import annotations
import argparse, re, json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pattern", help="regex (case-insensitive)")
    ap.add_argument("--ext", default=".lua", help="file extension filter")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--max", type=int, default=80)
    args = ap.parse_args()
    rx = re.compile(args.pattern, re.I)
    hits = []
    for p in ROOT.rglob(f"*{args.ext}"):
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        if "tools" in rel and p.suffix == ".py":
            continue
        try:
            lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except Exception:
            continue
        for i, line in enumerate(lines, 1):
            if rx.search(line):
                hits.append({"path": rel, "line": i, "text": line.strip()[:200]})
                if len(hits) >= args.max:
                    break
        if len(hits) >= args.max:
            break
    if args.json:
        print(json.dumps({"pattern": args.pattern, "hits": hits}, indent=2))
    else:
        print(f"{len(hits)} hits for /{args.pattern}/")
        for h in hits:
            print(f"  {h['path']}:{h['line']}: {h['text']}")

if __name__ == "__main__":
    main()
