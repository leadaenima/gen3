#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
base=json.loads((R/'tools/baselines/8.1.51-runtime-sha256.json').read_text())['files']
allowed_changed={
 'config.lua','lib/Audio.lua','lib/Config.lua','lib/DistantWeather.lua','lib/DramalessAtmos.lua',
 'lib/EngineRuntime.lua','lib/HostAdapter.lua','lib/Settings.lua','lib/StormCells.lua',
 'lib/WeatherState.lua','lib/WeatherWorldSpace.lua','lib/voxel_atmos/CinematicAtmos.lua'
}
changed=[];bad=[]
for rel,exp in base.items():
    p=R/rel
    if not p.exists(): print('FAIL missing 8.1.51 runtime '+rel);bad.append(rel);continue
    got=(hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_size);want=(exp['sha256'],exp['size'])
    if got!=want:
        changed.append(rel)
        if rel not in allowed_changed: bad.append(rel)
for rel in sorted(changed): print(('PASS intended runtime delta ' if rel in allowed_changed else 'FAIL unexpected runtime delta ')+rel)
for rel in sorted(allowed_changed-set(changed)): print('FAIL required runtime repair missing '+rel);bad.append(rel)
print(f'8.1.52 runtime delta: changed={sorted(changed)} unexpected={sorted(set(bad))}')
sys.exit(1 if bad else 0)
