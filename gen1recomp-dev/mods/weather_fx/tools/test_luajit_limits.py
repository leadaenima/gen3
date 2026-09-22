#!/usr/bin/env python3
"""Static LuaJIT closure-limit guard for Weather FX 3D precipitation.

LuaJIT 2.1 has a hard maximum of 60 upvalues per Lua function. A previous
WorldPrecip.update captured 67 and therefore could not compile on the real game
runtime even though Lua 5.3 headless tests accepted it. This source-level guard
runs even when no Lua interpreter is installed.
"""
from __future__ import annotations
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "lib/voxel_atmos/WorldPrecip.lua"
LIMIT = 60
HEADROOM_LIMIT = 55


def strip_lua(src: str) -> str:
    # Preserve byte positions/newlines while blanking comments and strings.
    out: list[str] = []
    i, n = 0, len(src)
    while i < n:
        if src.startswith("--[[", i):
            j = src.find("]]", i + 4)
            j = n - 2 if j < 0 else j
            out.append(" " * (j + 2 - i)); i = j + 2
        elif src.startswith("--", i):
            j = src.find("\n", i + 2)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif src.startswith("[[", i):
            j = src.find("]]", i + 2)
            j = n - 2 if j < 0 else j
            out.append(" " * (j + 2 - i)); i = j + 2
        elif src[i] in ("'", '"'):
            q = src[i]; j = i + 1
            while j < n:
                if src[j] == "\\": j += 2; continue
                if src[j] == q: j += 1; break
                j += 1
            out.append(" " * (j - i)); i = j
        else:
            out.append(src[i]); i += 1
    return "".join(out)


def top_level_locals(code: str) -> list[str]:
    names: list[str] = []
    for line in code.splitlines():
        if not line.startswith("local "):
            continue
        tail = line[6:]
        if tail.startswith("function "):
            m = re.match(r"function\s+([A-Za-z_]\w*)", tail)
            if m: names.append(m.group(1))
        else:
            left = tail.split("=", 1)[0]
            for item in left.split(","):
                item = item.strip()
                if re.fullmatch(r"[A-Za-z_]\w*", item): names.append(item)
    return names


def update_upvalue_estimate(src: str) -> tuple[int, list[str]]:
    code = strip_lua(src)
    start = src.index("function WP.update")
    marker = "\nend\n\n-- ---------------------------------------------------------------------------\n-- VERTEX BUFFER"
    end = src.index(marker, start) + 5
    body = code[start:end]
    top = top_level_locals(code)
    refs = [n for n in top if re.search(r"\b" + re.escape(n) + r"\b", body)]
    locals_in = {"dt", "focus", "weather", "streamMeta"}
    for m in re.finditer(r"\blocal\s+function\s+([A-Za-z_]\w*)", body):
        locals_in.add(m.group(1))
    for m in re.finditer(r"\blocal\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*=", body):
        for item in m.group(1).split(","):
            locals_in.add(item.strip())
    refs = [n for n in refs if n not in locals_in and n != "WP"]
    return len(refs), refs


def main() -> int:
    src = SRC.read_text(encoding="utf-8")
    n, refs = update_upvalue_estimate(src)
    print(f"LuaJIT limit guard: WP.update estimated direct upvalues={n}; hard={LIMIT}; ship={HEADROOM_LIMIT}")
    if n > HEADROOM_LIMIT:
        print("FAIL: WorldPrecip.update is too close to/exceeds LuaJIT's 60-upvalue compiler limit")
        print("captures:", ", ".join(refs))
        return 1
    if "local UPDATE_CONST" not in src:
        print("FAIL: LuaJIT-safe grouped immutable dependency table missing")
        return 1
    print("PASS: WorldPrecip.update has LuaJIT compiler headroom")
    return 0

if __name__ == "__main__":
    sys.exit(main())
