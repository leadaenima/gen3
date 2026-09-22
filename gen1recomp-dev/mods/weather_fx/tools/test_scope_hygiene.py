#!/usr/bin/env python3
"""Scope hygiene: forward references and global leaks.

Two failure classes that have each shipped in this mod more than once, and both
are SILENT because the call sites are pcall-wrapped:

  * FORWARD REFERENCE -- a `local function` called above its own declaration
    resolves to a nil global and throws. `getGrainShader` shipped this way (no
    3D snow at all); `otherUiOwnsBanners` shipped it twice (double route
    banners); `dwellFor` shipped it in the weather-advance path.

  * BOOT-TIME ENGINE CAPTURE -- `local Game = require("src...")` at file scope
    can permanently bind the Gen-1 implementation before a Gold boot installs
    its proxy. Engine modules must be resolved at call time.

  * GLOBAL LEAK -- `function f()` or `f = ...` at file scope writes to _G, where
    any other mod in the same VM can read or clobber it. Generic names like
    `lerp` and `mixColor` are exactly what a second mod is likely to define too,
    and the resulting conflict is intermittent and very hard to trace here.

Skips GLSL: shader source lives in [[...]] blocks and its built-ins (mix, clamp)
are not Lua functions.
"""
# Forward references: a `local function f` CALLED above its own declaration
# resolves to a nil global and throws. This has bitten twice (getGrainShader,
# otherUiOwnsBanners), and both times it was silent because the call site was
# inside a pcall.
import re, pathlib, sys
bad = []
for p in sorted(pathlib.Path("lib").rglob("*.lua")) + [pathlib.Path("main.lua")]:
    src = p.read_text()
    # Shader source lives in [[...]] blocks; its built-ins (mix, clamp, pow) are
    # not Lua functions and must not be scanned as such.
    src = re.sub(r"\[\[.*?\]\]", '""', src, flags=re.S)
    lines = src.split("\n")
    # strip comments and string literals crudely
    clean = []
    for l in lines:
        l = re.sub(r'--.*$', '', l)
        l = re.sub(r'"[^"]*"', '""', l)
        l = re.sub(r"'[^']*'", "''", l)
        clean.append(l)
    decl = {}
    for i, l in enumerate(clean):
        m = re.match(r'\s*local function ([A-Za-z_][A-Za-z0-9_]*)\s*\(', l)
        if m and m.group(1) not in decl:
            decl[m.group(1)] = i
        m2 = re.match(r'\s*local ([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function', l)
        if m2 and m2.group(1) not in decl:
            decl[m2.group(1)] = i
    for name, dline in decl.items():
        for i in range(0, dline):
            l = clean[i]
            if re.search(r'(?<![.:\w])' + re.escape(name) + r'\s*\(', l):
                # ignore a forward `local name` declaration above
                if re.match(r'\s*local\s+' + re.escape(name) + r'\b', clean[i]):
                    continue
                bad.append((str(p), i+1, dline+1, name, clean[i].strip()[:70]))
                break

# --- boot-time engine captures ----------------------------------------------
ENGINE_CAPTURE_BAD = False
engine_hits = []
for p in sorted(pathlib.Path("lib").rglob("*.lua")) + [pathlib.Path("main.lua")]:
    for i, line in enumerate(p.read_text().split("\n"), 1):
        # No indentation = file scope. Both direct require and the historical
        # tryRequire wrapper are unsafe here for src.* engine modules.
        if re.match(r'^local\s+[A-Za-z_]\w*\s*=\s*(?:tryRequire|require)\("src\.', line):
            engine_hits.append((str(p), i, line.strip()))
if engine_hits:
    for f, l, text in engine_hits:
        print(f"ENGINE-CAPTURE {f}:{l}  {text}")
    print(f"\n{len(engine_hits)} boot-time engine capture(s)")
    ENGINE_CAPTURE_BAD = True

# --- global leaks -----------------------------------------------------------
GLOBAL_BAD = False
hits=[]
for p in sorted(pathlib.Path("lib").rglob("*.lua"))+[pathlib.Path("main.lua")]:
    src=p.read_text()
    src=re.sub(r'\[\[.*?\]\]','""',src,flags=re.S)
    for i,l in enumerate(src.split("\n")):
        l2=re.sub(r'--.*$','',l)
        m=re.match(r'^function ([A-Za-z_]\w*)\s*\(', l2)
        if m: hits.append((str(p), i+1, "function "+m.group(1)))
        m2=re.match(r'^([A-Za-z_]\w*)\s*=\s*[^=]', l2)
        if m2 and m2.group(1) not in ("_G",):
            # An assignment to a name FORWARD-DECLARED as a local earlier in the
            # file is not a global. Runtime-verified separately: loading these
            # modules leaves nothing new in _G.
            nm = m2.group(1)
            if re.search(r"^local [^\n]*\b" + re.escape(nm) + r"\b", src, re.M):
                continue
            hits.append((str(p), i+1, nm+" ="))
if hits:
    for f,l,n in hits: print(f"GLOBAL {f}:{l}  {n}")
    print(f"\n{len(hits)} global definition(s)")
    GLOBAL_BAD = True


if bad:
    for f, use, dec, n, txt in bad:
        print(f"FORWARD-REF {f}:{use} calls '{n}' declared at line {dec}  ::  {txt}")
    print(f"\n{len(bad)} forward reference(s)")
    sys.exit(1)
if GLOBAL_BAD or ENGINE_CAPTURE_BAD:
    sys.exit(1)
print("PASS scope hygiene (no forward references, global leaks, or boot-time engine captures)")
