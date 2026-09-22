#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
base=json.loads((R/'tools/baselines/8.1.39-runtime-sha256.json').read_text())['files']
allowed={'lib/DramalessAtmos.lua'}
changed=[];bad=[]
for rel,exp in base.items():
    p=R/rel
    if not p.exists(): print('FAIL missing '+rel);bad.append(rel);continue
    got=(hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_size);want=(exp['sha256'],exp['size'])
    if got!=want: changed.append(rel)
    if rel not in allowed and got!=want: bad.append(rel)
for rel in sorted(changed): print(('PASS intended runtime delta ' if rel in allowed else 'FAIL unexpected runtime delta ')+rel)
for rel in sorted(allowed-set(changed)): print('FAIL intended delta missing '+rel);bad.append(rel)
print(f'8.1.40 runtime preservation: changed={sorted(changed)} unexpected={sorted(set(bad))}')
sys.exit(1 if bad else 0)
