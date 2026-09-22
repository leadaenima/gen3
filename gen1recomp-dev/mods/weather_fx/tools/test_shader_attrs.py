# A shader that declares an attribute the mesh format does not have receives no
# per-vertex data and draws nothing -- silently. That is how the new leaf shader
# shipped with leaves invisible: it declared `LeafTint` while the shared grain
# vertex format supplies `SnowTint`.
import re, pathlib, sys
src = pathlib.Path("lib/voxel_atmos/WorldPrecip.lua").read_text()
fmts = set()
# Every custom attribute declared in a mesh vertex format is valid. The older
# audit only recognized names ending in Tint, which incorrectly rejected the
# 8.0.1 per-instance snow attributes.
for m in re.finditer(r'\{\s*"([A-Za-z][A-Za-z0-9_]*)"\s*,\s*"float"', src):
    fmts.add(m.group(1))
attrs = {}
for m in re.finditer(r'attribute vec4 ([A-Za-z]+);', src):
    ln = src[:m.start()].count("\n") + 1
    attrs.setdefault(m.group(1), []).append(ln)
bad = [(n, ls) for n, ls in attrs.items() if n not in fmts]
print("vertex formats declare:", ", ".join(sorted(fmts)))
if bad:
    for n, ls in bad:
        print(f"FAIL shader attribute '{n}' (line(s) {ls}) is not in any vertex "
              f"format -- that shader gets no vertex data and draws nothing")
    sys.exit(1)
# --- non-portable GLSL --------------------------------------------------
# A shader that fails to COMPILE is silent here: newShader is pcall-wrapped and
# the caller falls through, so the effect just never appears. Derivative
# functions need GL_OES_standard_derivatives on GLES targets and are the most
# likely thing to fail that way. No shader in this file needs them.
# Strip GLSL // comments and Lua -- comments first: the fix for this very bug
# is documented in a comment that NAMES fwidth, and a first version matched its
# own documentation and failed against a correct tree.
code = re.sub(r"//[^\n]*", "", src)
code = "\n".join(l for l in code.split("\n") if not l.lstrip().startswith("--"))
risky = []
for fn in ("fwidth", "dFdx", "dFdy"):
    for m in re.finditer(r"\b" + fn + r"\s*\(", code):
        risky.append((fn, code[:m.start()].count("\n") + 1))
if risky:
    for fn, ln in risky:
        print(f"FAIL {fn}() at line {ln} needs derivative support that is not "
              f"guaranteed. If it is unavailable the shader fails to compile "
              f"SILENTLY and that effect stops drawing entirely.")
    sys.exit(1)

print("PASS shader attributes exist, and no non-portable GLSL")
