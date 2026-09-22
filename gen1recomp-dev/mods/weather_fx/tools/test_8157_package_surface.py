#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text());ck(man.get('version')=='8.1.57','manifest 8.1.57');ck((R/'BASELINE').read_text().strip()=='8.1.57','BASELINE 8.1.57')
for f in ['RELEASE-NOTES-8.1.57.md','tools/test_8157_runtime_delta.py','tools/test_8157_runtime_freeze.py','tools/test_8157_package_surface.py','tools/test_8157_2d_tornado_contract.py','tests/tornado_2d_relocation_8157_test.lua','tests/funnel_left_to_right_8157_test.lua','tools/baselines/8.1.57-runtime-sha256.json']:
 ck((R/f).exists(),f+' present')
print(f'8.1.57 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
