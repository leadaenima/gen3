#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m):checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.29','manifest 8.1.29')
ck((R/'BASELINE').read_text().strip()=='8.1.29','BASELINE marker 8.1.29')
for f in ['RELEASE-NOTES-8.1.29.md','lib/ConnectedWater.lua','lib/voxel_atmos/ConnectedWater3D.lua','tools/test_8129_connected_water.py','tests/connected_water_test.lua','tests/connected_water_3d_test.lua','tests/snow_on_ice_test.lua','tools/test_8129_runtime_freeze.py','tools/baselines/8.1.29-runtime-sha256.json']:
 ck((R/f).exists(),f+' exists')
notes=(R/'RELEASE-NOTES-8.1.29.md').read_text()
ck('does **not** add more weather names' in notes,'weather breadth intentionally unchanged')
ck('No mountain' in notes or 'no mountain' in notes.lower(),'flat-world/no-mountain contract stated')
ck('No particle count or visual-quality target is reduced' in notes,'no-quality-loss contract stated')
ck('movement.collision' in notes and 'Surf' in notes,'ice collision/Surf safety documented')
failed=sum(not v for v,_ in checks);print(f'8.1.29 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
