#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m):checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.55','manifest 8.1.55')
ck((R/'BASELINE').read_text().strip()=='8.1.55','BASELINE 8.1.55')
for f in ['RELEASE-NOTES-8.1.55.md','PERFORMANCE-AUDIT-8.1.55.md','WEATHER-FX-8.1.55-FINAL-AUDIT.md','tools/test_8155_runtime_delta.py','tools/test_8155_runtime_freeze.py','tools/test_8155_package_surface.py','tools/test_8155_performance_contract.py','tests/snow_motion_8155_test.lua','tools/baselines/8.1.55-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
ps=(R/'lib/ProceduralSnowField.lua').read_text()
ck('local ANCHOR_CELL=256' in ps and 'submitFixed' in ps and 'anchorFromX' not in ps,'fixed world-anchor snow streaming present')
ck('presentationTime' in ps and 'love.timer.getTime' in ps,'dedicated presentation clock present')
ck('local newCount=0' in ps and 'local oldCount=count-newCount' in ps,'handoff partitions unchanged particle population')
print(f'8.1.55 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
