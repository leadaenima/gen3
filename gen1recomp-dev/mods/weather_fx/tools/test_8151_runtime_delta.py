#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
base=json.loads((R/'tools/baselines/8.1.50-runtime-sha256.json').read_text())['files']
allowed_changed={'lib/voxel_atmos/CinematicAtmos.lua'}
required_new={'lib/DistantFrontPrecip.lua'}
changed=[];bad=[]
for rel,exp in base.items():
    p=R/rel
    if not p.exists(): print('FAIL missing baseline runtime '+rel);bad.append(rel);continue
    got=(hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_size);want=(exp['sha256'],exp['size'])
    if got!=want:
        changed.append(rel)
        if rel not in allowed_changed: bad.append(rel)
for rel in sorted(changed): print(('PASS intended existing-runtime delta ' if rel in allowed_changed else 'FAIL unexpected existing-runtime delta ')+rel)
for rel in sorted(allowed_changed-set(changed)): print('FAIL required existing-runtime delta missing '+rel);bad.append(rel)
for rel in sorted(required_new):
    p=R/rel
    ok=p.exists() and p.stat().st_size>0
    print(('PASS new runtime module ' if ok else 'FAIL missing new runtime module ')+rel)
    if not ok: bad.append(rel)
print(f'8.1.51 runtime preservation: existing_changed={sorted(changed)} new={sorted(required_new)} unexpected={sorted(set(bad))}')
sys.exit(1 if bad else 0)
