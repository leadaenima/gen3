#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
base=json.loads((R/'tools/baselines/8.1.41-runtime-sha256.json').read_text())['files']
allowed_changed={
 'lib/DistantWeather.lua',
 'lib/DramalessAtmos.lua',
 'lib/NightSky.lua',
 'lib/Settings.lua',
 'lib/voxel_atmos/CinematicAtmos.lua',
}
allowed_new={'lib/Aurora.lua'}
changed=[];bad=[]
for rel,exp in base.items():
    p=R/rel
    if not p.exists():
        print('FAIL missing '+rel);bad.append(rel);continue
    got=(hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_size)
    want=(exp['sha256'],exp['size'])
    if got!=want:
        changed.append(rel)
        if rel not in allowed_changed: bad.append(rel)
for rel in sorted(changed): print(('PASS intended runtime delta ' if rel in allowed_changed else 'FAIL unexpected runtime delta ')+rel)
for rel in sorted(allowed_changed-set(changed)):
    print('FAIL intended delta missing '+rel);bad.append(rel)
for rel in sorted(allowed_new):
    p=R/rel
    if p.exists() and p.stat().st_size>0: print('PASS intended new runtime '+rel)
    else: print('FAIL intended new runtime missing '+rel);bad.append(rel)
print(f'8.1.42 runtime preservation: changed={sorted(changed)} new={sorted(allowed_new)} unexpected={sorted(set(bad))}')
sys.exit(1 if bad else 0)
