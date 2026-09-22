#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
base=json.loads((R/'tools/baselines/8.1.59-runtime-sha256.json').read_text())['files']
allowed={'main.lua','lib/Draw.lua','lib/Lightning.lua','lib/voxel_atmos/NpcLightning.lua'}
new_required={'lib/NpcLightning2D.lua'}
changed=[];bad=[]
for rel,exp in base.items():
    p=R/rel
    if not p.exists():
        print('FAIL missing '+rel);bad.append(rel);continue
    got=(hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_size)
    want=(exp['sha256'],exp['size'])
    if got!=want:
        changed.append(rel)
        if rel not in allowed: bad.append(rel)
for rel in sorted(changed): print(('PASS intended runtime delta ' if rel in allowed else 'FAIL unexpected runtime delta ')+rel)
for rel in sorted(allowed-set(changed)):
    print('FAIL required 8.1.60 change missing '+rel);bad.append(rel)
for rel in sorted(new_required):
    p=R/rel
    ok=p.exists() and p.stat().st_size>500
    print(('PASS ' if ok else 'FAIL ')+rel+' new runtime module present')
    if not ok: bad.append(rel)
print(f'8.1.60 runtime delta changed={sorted(changed)} new={sorted(new_required)}')
sys.exit(1 if bad else 0)
