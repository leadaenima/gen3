#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];m=json.loads((R/'manifest.json').read_text());checks=[]
def ck(v,msg): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck(m.get('version')=='8.1.68','manifest 8.1.68');ck((R/'BASELINE').read_text().strip()=='8.1.68','BASELINE 8.1.68')
for rel in [
 'RELEASE-NOTES-8.1.68.md','lib/SnowPack.lua','lib/SnowSurfacePaint.lua','lib/voxel_atmos/WorldPrecip.lua',
 'tests/snow_bank_distribution_8168_test.lua','tools/test_8168_snowbank_contract.py','tools/test_8168_runtime_delta.py',
 'tools/test_8168_runtime_freeze.py','tools/test_8168_package_surface.py','tools/baselines/8.1.68-runtime-sha256.json']:
 ck((R/rel).is_file(),rel+' present')
print(f'8.1.68 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
