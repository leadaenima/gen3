#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];m=json.loads((R/'manifest.json').read_text());checks=[]
def ck(v,msg):checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck(m.get('version')=='8.1.62','manifest 8.1.62')
ck((R/'BASELINE').read_text().strip()=='8.1.62','BASELINE 8.1.62')
for rel in ['RELEASE-NOTES-8.1.62.md','WEATHER-FX-8.1.62-FINAL-AUDIT.md','tests/tornado_walk_contact_8162_test.lua','tools/test_8162_runtime_delta.py','tools/test_8162_runtime_freeze.py','tools/test_8162_tornado_contact_contract.py','tools/baselines/8.1.62-runtime-sha256.json']:
 ck((R/rel).is_file(),rel+' present')
print(f'8.1.62 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
