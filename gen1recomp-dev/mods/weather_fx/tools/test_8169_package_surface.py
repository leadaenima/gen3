#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];m=json.loads((R/'manifest.json').read_text());checks=[]
def ck(v,msg): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck(m.get('version')=='8.1.69','manifest 8.1.69');ck((R/'BASELINE').read_text().strip()=='8.1.69','BASELINE 8.1.69')
for rel in ['RELEASE-NOTES-8.1.69.md','lib/Settings.lua','lib/SnowPack.lua','lib/voxel_atmos/WorldPrecip.lua','tests/snow_accumulation_setting_8169_test.lua','tools/test_8169_setting_contract.py','tools/test_8169_runtime_delta.py','tools/test_8169_runtime_freeze.py','tools/test_8169_package_surface.py','tools/baselines/8.1.69-runtime-sha256.json']:
 ck((R/rel).is_file(),rel+' present')
print(f'8.1.69 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
