#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.28','manifest 8.1.28')
ck((R/'BASELINE').read_text().strip()=='8.1.28','BASELINE marker 8.1.28')
for f in ['RELEASE-NOTES-8.1.28.md','tools/test_8128_runtime_freeze.py','tools/test_8128_world_scale_realism.py','tests/world_scale_realism_test.lua','tests/snow_accumulation_footprint_test.lua','tests/snow_radial_surface_test.lua','tests/snow_3d_bank_water_test.lua','tools/baselines/8.1.28-runtime-sha256.json']:
 ck((R/f).exists(),f+' exists')
notes=(R/'RELEASE-NOTES-8.1.28.md').read_text()
ck('no mountains' in notes.lower() or 'no mountain' in notes.lower(),'release notes state flat-world/no-mountain contract')
ck('does **not** add more weather names' in notes,'release notes state breadth is intentionally unchanged')
ck('No particle count or visual-quality target is reduced' in notes,'release notes preserve no-quality-loss contract')
ck('sand/ash' in notes and 'blue rain shafts' in notes,'release notes guard dry distant-weather ownership')
failed=sum(not v for v,_ in checks)
print(f'8.1.28 package surface: {len(checks)-failed}/{len(checks)} passed')
sys.exit(1 if failed else 0)
