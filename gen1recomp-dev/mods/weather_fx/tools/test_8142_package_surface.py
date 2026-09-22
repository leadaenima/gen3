#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.42','manifest 8.1.42')
ck((R/'BASELINE').read_text().strip()=='8.1.42','BASELINE marker 8.1.42')
for f in ['lib/Aurora.lua','AURORA-RESEARCH-8.1.42.md','RELEASE-NOTES-8.1.42.md','tests/winter_aurora_8142_test.lua','tests/winter_snow_front_8142_test.lua','tools/test_8142_winter_aurora_contract.py','tools/test_8142_package_surface.py','tools/test_8142_runtime_delta.py','tools/test_8142_runtime_freeze.py','tools/baselines/8.1.41-runtime-sha256.json','tools/baselines/8.1.42-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
rn=(R/'RELEASE-NOTES-8.1.42.md').read_text(); ar=(R/'AURORA-RESEARCH-8.1.42.md').read_text()
ck('NASA/NOAA' in rn and 'year-round' in rn and 'winter' in rn and '557.7' in ar and '630.0' in ar,'research basis + winter gameplay distinction documented')
ck('8.1.41' in rn and '8.1.40' in rn and 'VOID-water' in rn,'front + water baseline preservation documented')
failed=sum(not v for v,_ in checks);print(f'8.1.42 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
