#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.43','manifest 8.1.43')
ck((R/'BASELINE').read_text().strip()=='8.1.43','BASELINE marker 8.1.43')
for f in ['RELEASE-NOTES-8.1.43.md','CONSTELLATION-BRIGHTNESS-AUDIT-8.1.43.csv','tests/constellation_peak_brightness_8143_test.lua','tools/test_8143_constellation_contract.py','tools/test_8143_package_surface.py','tools/test_8143_runtime_delta.py','tools/test_8143_runtime_freeze.py','tools/baselines/8.1.42-runtime-sha256.json','tools/baselines/8.1.43-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
rn=(R/'RELEASE-NOTES-8.1.43.md').read_text()
ck('0.7872' in rn and '0.5986' in rn and '8,507' in rn,'exact primary/secondary peak audit documented')
ck('8.1.42' in rn and '8.1.41' in rn and '8.1.40' in rn,'recent baseline preservation documented')
failed=sum(not v for v,_ in checks);print(f'8.1.43 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
