#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];m=json.loads((R/'manifest.json').read_text());checks=[]
def ck(v,msg): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck(m.get('version')=='8.1.65','manifest 8.1.65'); ck((R/'BASELINE').read_text().strip()=='8.1.65','BASELINE 8.1.65')
for rel in ['RELEASE-NOTES-8.1.65.md','WEATHER-FX-8.1.65-FINAL-AUDIT.md','tests/tornado_remote_map_roam_8165_test.lua','tests/tornado_remote_render_cull_8165_test.lua','tools/test_8165_runtime_delta.py','tools/test_8165_runtime_freeze.py','tools/test_8165_package_surface.py','tools/test_8165_tornado_map_roam_contract.py','tools/baselines/8.1.65-runtime-sha256.json']:
 ck((R/rel).is_file(),rel+' present')
print(f'8.1.65 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
