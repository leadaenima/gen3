#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
base=json.loads((R/'tools/baselines/8.1.68-runtime-sha256.json').read_text())['files']
allowed={'lib/Settings.lua','lib/SnowPack.lua','lib/voxel_atmos/WorldPrecip.lua'}
changed=[];bad=[]
for rel,exp in base.items():
 p=R/rel
 if not p.exists(): print('FAIL missing '+rel);bad.append(rel);continue
 got=(hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_size);want=(exp['sha256'],exp['size'])
 if got!=want:
  changed.append(rel)
  if rel not in allowed: bad.append(rel)
for rel in sorted(changed): print(('PASS intended runtime delta ' if rel in allowed else 'FAIL unexpected runtime delta ')+rel)
for rel in sorted(allowed-set(changed)): print('FAIL required 8.1.69 change missing '+rel);bad.append(rel)
extra=[]
for p in list(R.glob('*.lua'))+list((R/'lib').rglob('*.lua')):
 rel=p.relative_to(R).as_posix()
 if rel not in base: extra.append(rel)
for rel in sorted(extra): print('FAIL unexpected new runtime '+rel);bad.append(rel)
print(f'8.1.69 runtime delta changed={sorted(changed)}')
sys.exit(1 if bad else 0)
