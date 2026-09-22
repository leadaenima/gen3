#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.45','manifest 8.1.45');ck((R/'BASELINE').read_text().strip()=='8.1.45','BASELINE marker 8.1.45')
for f in ['RELEASE-NOTES-8.1.45.md','tests/voxel_nexus_water_8145_test.lua','tools/test_8145_voxel_nexus_contract.py','tools/test_8145_package_surface.py','tools/test_8145_runtime_delta.py','tools/test_8145_runtime_freeze.py','tools/baselines/8.1.44-runtime-sha256.json','tools/baselines/8.1.45-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
rn=(R/'RELEASE-NOTES-8.1.45.md').read_text()
ck('WaterEngine.tideOffset' in rn and '32,768' in rn and '96px' in rn,'Nexus overlap + VOID performance root causes documented')
ck('8.1.44' in rn and 'public Battle Art' in rn,'8.1.44 public Battle Art behavior explicitly preserved')
failed=sum(not v for v,_ in checks);print(f'8.1.45 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
