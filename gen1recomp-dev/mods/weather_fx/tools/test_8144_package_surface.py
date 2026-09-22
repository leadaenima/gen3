#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.44','manifest 8.1.44')
ck((R/'BASELINE').read_text().strip()=='8.1.44','BASELINE marker 8.1.44')
for f in ['RELEASE-NOTES-8.1.44.md','tests/battle_art_public_water_8144_test.lua','tools/test_8144_public_battle_art_contract.py','tools/test_8144_package_surface.py','tools/test_8144_runtime_delta.py','tools/test_8144_runtime_freeze.py','tools/baselines/8.1.43-runtime-sha256.json','tools/baselines/8.1.44-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
rn=(R/'RELEASE-NOTES-8.1.44.md').read_text()
ck('Battle Art Voxel Fork 1.10.1' in rn and '_trainSource' in rn and 'WAVE_HEIGHT' in rn,'public Battle Art 1.10.1 root cause documented')
ck('8.1.43' in rn and '8.1.42' in rn and '8.1.41' in rn and '8.1.40' in rn,'recent baselines preserved')
failed=sum(not v for v,_ in checks);print(f'8.1.44 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
