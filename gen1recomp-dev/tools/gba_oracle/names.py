"""Flag, var and special names, read from pokeruby headers.

Names make an oracle report worth reading: "FLAG_HIDE_RIVAL_BIRCH_LAB set
on the cart but not in the engine" is a bug report, "flag 0x2D1 differs"
is a puzzle.  The headers are looked for in a few likely places and the
tool degrades to bare numbers when they are absent, so nothing here is a
hard dependency.

Point POKERUBY at a decomp checkout to override the search.
"""

import os
import re

_HERE = os.path.dirname(os.path.abspath(__file__))

SEARCH = [
    os.environ.get("POKERUBY", ""),
    os.path.join(_HERE, "pokeruby"),
    os.path.expanduser("~/Desktop/pokeruby-master/pokeruby-master"),
    os.path.expanduser("~/Desktop/pokeruby-master"),
    os.environ.get("TEMP", ""),
]

_DEFINE = re.compile(
    r"^#define\s+([A-Z0-9_]+)\s+(0x[0-9A-Fa-f]+|\d+)\s*(?://.*)?$")
_DEFINE_COMMENT = re.compile(
    r"^#define\s+([A-Z0-9_]+)\s+.+\s+//\s*(0x[0-9A-Fa-f]+)\s*$")
_DEFINE_OFFSET = re.compile(
    r"^#define\s+([A-Z0-9_]+)\s+\(\s*([A-Z0-9_]+)\s*\+\s*(0x[0-9A-Fa-f]+|\d+)\s*\)")


def _find(*relatives):
    for root in SEARCH:
        if not root:
            continue
        for rel in relatives:
            path = os.path.join(root, rel)
            if os.path.exists(path):
                return path
    return None


def _defines(path):
    """Parse #define NAME value, including (BASE + n) and // 0xNN comments.

    SYSTEM_FLAGS and FLAG_VISITED_* are written as expressions.  Without
    those, an oracle delta prints "flag 0x80F" instead of the town name.
    """
    out = {}
    if not path:
        return out
    pending = []
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            m = _DEFINE.match(line)
            if m:
                out[m.group(1)] = int(m.group(2), 0)
                continue
            m = _DEFINE_COMMENT.match(line)
            if m:
                out[m.group(1)] = int(m.group(2), 0)
                continue
            m = _DEFINE_OFFSET.match(line)
            if m:
                pending.append((m.group(1), m.group(2), int(m.group(3), 0)))
    changed = True
    while changed and pending:
        changed = False
        keep = []
        for name, base, off in pending:
            if base in out:
                out[name] = out[base] + off
                changed = True
            else:
                keep.append((name, base, off))
        pending = keep
    return out


def _invert(defines, skip=()):
    by_value = {}
    for name, value in defines.items():
        if name in skip or name.endswith("_COUNT") or name.endswith("_START"):
            continue
        # First name wins: later ones are usually aliases of the same slot.
        by_value.setdefault(value, name)
    return by_value


_flag_defs = _defines(_find("include/constants/flags.h", "flags.h"))
_var_defs = _defines(_find("include/constants/vars.h", "vars.h"))
_flags = _invert(_flag_defs, skip=("SYSTEM_FLAGS",))
_vars = _invert(_var_defs, skip=("VARS_START",))


def flag_id(name):
    return _flag_defs.get(name)


def var_id(name):
    return _var_defs.get(name)


def flag(flag_id):
    name = _flags.get(flag_id)
    return "%s (0x%03X)" % (name, flag_id) if name else "flag 0x%03X" % flag_id


def var(var_id):
    name = _vars.get(var_id)
    return "%s (0x%04X)" % (name, var_id) if name else "var 0x%04X" % var_id


def have_names():
    return bool(_flags) and bool(_vars)


def specials(path=None):
    """Ordinal -> function name, from pokeruby data/specials.inc.

    The table is a run of `def_special <fn>` lines starting at zero, which
    is exactly the id a script's `special` command carries.
    """
    path = path or _find("data/specials.inc", "specials.inc")
    out = {}
    if not path:
        return out
    i = 0
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"\s*def_special\s+(\w+)", line)
            if m:
                out[i] = m.group(1)
                i += 1
    return out
