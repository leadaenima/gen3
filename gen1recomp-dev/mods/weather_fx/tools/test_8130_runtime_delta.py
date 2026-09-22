#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
base=json.loads((R/'tools/baselines/8.1.29-runtime-sha256.json').read_text())['files']
allowed={'lib/voxel_atmos/ConnectedWater3D.lua'}
actual={}
for rel in base:
    p=R/rel
    if not p.exists():
        print('FAIL missing '+rel);sys.exit(1)
    raw=p.read_bytes();actual[rel]=(hashlib.sha256(raw).hexdigest(),len(raw))
changed=[];bad=[]
for rel,exp in base.items():
    got=actual[rel]
    if got!=(exp['sha256'],exp['size']): changed.append(rel)
    if rel not in allowed and got!=(exp['sha256'],exp['size']): bad.append(rel)
for rel in sorted(changed): print(('PASS intended runtime delta ' if rel in allowed else 'FAIL unexpected runtime delta ')+rel)
if not allowed.issubset(changed):
    for rel in sorted(allowed-set(changed)): print('FAIL intended delta missing '+rel)
    bad += list(allowed-set(changed))
print(f'8.1.30 runtime preservation: changed={sorted(changed)} unexpected={sorted(set(bad))}')
sys.exit(1 if bad else 0)
