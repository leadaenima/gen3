#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];m=json.loads((R/'manifest.json').read_text());checks=[]
def ck(v,msg): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck(m.get('version')=='8.1.63','manifest 8.1.63')
ck((R/'BASELINE').read_text().strip()=='8.1.63','BASELINE 8.1.63')
for rel in ['RELEASE-NOTES-8.1.63.md','WEATHER-FX-8.1.63-FINAL-AUDIT.md','WEATHER-FX-8.1.63-TORNADO-PICKUP-LIVE-PROOF.md','tests/tornado_pickup_semantics_8163_test.lua','tools/test_8163_runtime_delta.py','tools/test_8163_runtime_freeze.py','tools/test_8163_package_surface.py','tools/test_8163_tornado_pickup_contract.py','tools/baselines/8.1.63-runtime-sha256.json']:
 ck((R/rel).is_file(),rel+' present')
print(f'8.1.63 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
