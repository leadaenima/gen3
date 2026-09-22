#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];c=[]
def ck(v,m): c.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.59','manifest 8.1.59')
ck((R/'BASELINE').read_text().strip()=='8.1.59','BASELINE 8.1.59')
for f in ['RELEASE-NOTES-8.1.59.md','tools/test_8159_runtime_delta.py','tools/test_8159_runtime_freeze.py','tools/test_8159_package_surface.py','tools/test_8159_snow_plume_contract.py','tests/snow_point_plume_8159_test.lua','tools/baselines/8.1.59-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
print(f'8.1.59 package surface: {sum(c)}/{len(c)} passed')
sys.exit(0 if all(c) else 1)
