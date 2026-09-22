"""Check every shipped runtime Lua file against the engine's `love` sandbox.

Python walks the runtime tree directly, so this guard cannot silently stop
covering new modules because somebody forgot to update a hardcoded list.
Blocked APIs throw on index in the mod sandbox, so even guarded-looking access
like `if love and love.system then` is unsafe.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

BLOCKED = ["filesystem", "thread", "system", "event"]

SKIP_DIRS = {"tests", "tools"}

# No blocked API is allow-listed. Even a pcall-caught index-time exception is
# unacceptable on a hot path: it hides the violation and still pays exception
# overhead every call.
ALLOW = set()


def shipped_lua():
    out = []
    for p in sorted(ROOT.rglob("*.lua")):
        rel = p.relative_to(ROOT)
        if rel.parts and rel.parts[0] in SKIP_DIRS:
            continue
        out.append(rel.as_posix())
    return out


failures = []
files = shipped_lua()

# --- 1. no sandboxed love API on any shipped path ---------------------------
for rel in files:
    src = (ROOT / rel).read_text(encoding="utf8", errors="replace")
    for ln, line in enumerate(src.split("\n"), 1):
        if re.match(r"\s*--", line):
            continue          # the names are discussed in comments at length
        for name in BLOCKED:
            if re.search(r"\blove\." + name + r"\b", line):
                if (rel, name) in ALLOW:
                    continue
                failures.append(f"{rel}:{ln} touches sandboxed love.{name}")


if failures:
    for f in failures:
        print("FAIL " + f)
    sys.exit(1)

print(f"PASS love sandbox ({len(files)} shipped runtime Lua files scanned)")
