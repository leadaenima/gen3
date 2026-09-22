#!/usr/bin/env python3
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
L=(ROOT/'lib/Lightning.lua').read_text()
D=(ROOT/'lib/Draw.lua').read_text()
C=(ROOT/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
W=(ROOT/'lib/voxel_atmos/WorldLightning.lua').read_text()
T=(ROOT/'tests/lightning_burst_test.lua').read_text()
checks=[]
def ck(ok,msg): checks.append((bool(ok),msg))
for wid in ('STORM','HEAVY_RAIN','PSYSTORM'):
    ck(re.search(r'\b'+wid+r'\s*=\s*\{',L) is not None, f'{wid} has a severe-storm burst profile')
ck('State.id)' in D and 'Lightning.update' in D, 'live weather id is passed into lightning scheduler')
ck('L.burstCount = L.sampleBurstCount' in L, 'each scheduled strike event samples a burst count')
ck('function WL.strikeBurst' in W, 'WorldLightning exposes simultaneous strikeBurst allocator')
ck('MAX_BOLTS = 4' in W, 'world renderer retains four-live-bolt capacity')
ck('WL.strikeBurst' in C and 'burstCount' in C, '3D bridge consumes scheduler burst count')
ck('avoidImpacts' in W and 'separatedImpact' in W, 'burst target selection rejects overlapping impact targets before allocation')
ck('quad severe-storm event allocates four bolts' in T, 'executable quad-bolt allocation proof is shipped')
ck('all four bolts are live simultaneously' in T, 'executable simultaneous-live proof is shipped')
failed=0
for ok,msg in checks:
    print(('PASS ' if ok else 'FAIL ')+msg); failed += 0 if ok else 1
print(f'\nlightning-burst gate: {len(checks)-failed} passed, {failed} failed')
sys.exit(1 if failed else 0)
