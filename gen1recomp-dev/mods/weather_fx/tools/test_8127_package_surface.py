#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.27','manifest 8.1.27')
ck((R/'BASELINE').read_text().strip()=='8.1.27','BASELINE marker 8.1.27')
for f in ['RELEASE-NOTES-8.1.27.md','tools/test_8127_runtime_freeze.py','tools/test_8127_live_host_repairs.py','tools/baselines/8.1.27-runtime-sha256.json']:
 ck((R/f).exists(),f+' exists')
notes=(R/'RELEASE-NOTES-8.1.27.md').read_text()
ck('real in-game Gen1Recomp 0.2.53' in notes,'release notes document real-host qualification')
ck('no reductions to rain/snow/hail particle populations' in notes,'release notes preserve zero-quality contract')
ck('NightSky shader validation failure' in notes,'release notes document celestial shader repair')
f=sum(not v for v,_ in checks);print(f'8.1.27 package surface: {len(checks)-f}/{len(checks)} passed');sys.exit(1 if f else 0)
