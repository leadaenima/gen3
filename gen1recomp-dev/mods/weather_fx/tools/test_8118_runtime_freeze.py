#!/usr/bin/env python3
"""Byte-for-byte runtime freeze against the user-approved Weather FX 8.1.17 baseline.

This deliberately ignores tests/tools/docs/version metadata. Every executable Lua file,
compat runtime and shipped visual/audio asset is frozen. Intended future behavior changes
must explicitly regenerate this baseline; accidental drift fails immediately.
"""
from pathlib import Path
import hashlib, json, sys
R=Path(__file__).resolve().parents[1]
S=json.loads((R/'tools/baselines/8.1.17-runtime-sha256.json').read_text())

def runtime_files():
    out=[]
    for p in sorted(R.rglob('*')):
        if not p.is_file(): continue
        rel=p.relative_to(R).as_posix()
        if rel in ('main.lua','config.lua') or rel.startswith('assets/') or rel.startswith('compat/') or (rel.startswith('lib/') and not rel.endswith('.md')):
            out.append(rel)
    return out

actual=runtime_files(); expected=sorted(S['files'])
failed=[]; passed=0
if actual != expected:
    a,e=set(actual),set(expected)
    if a-e: failed.append('unexpected runtime files: '+', '.join(sorted(a-e)))
    if e-a: failed.append('missing runtime files: '+', '.join(sorted(e-a)))
else: passed += 1
for rel in expected:
    p=R/rel
    if not p.exists(): continue
    raw=p.read_bytes(); h=hashlib.sha256(raw).hexdigest(); sz=len(raw); exp=S['files'][rel]
    if h!=exp['sha256'] or sz!=exp['size']:
        failed.append(f'{rel}: baseline drift sha={h} size={sz}, expected sha={exp["sha256"]} size={exp["size"]}')
    else: passed += 1
print(f'8.1.17 runtime freeze: {passed}/{len(expected)+1} checks passed; frozen files={len(expected)}')
if failed:
    for x in failed[:40]: print('FAIL',x)
    if len(failed)>40: print(f'... {len(failed)-40} more failures')
    sys.exit(1)
print('PASS executable code + compat + assets are byte-identical to approved 8.1.17')
