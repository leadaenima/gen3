#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.26','manifest 8.1.26')
ck((R/'BASELINE').read_text().strip()=='8.1.26','BASELINE marker 8.1.26')
for f in ['RELEASE-NOTES-8.1.26.md','tools/test_8126_runtime_freeze.py','tools/test_8126_player_experience.py','tests/8126_celestial_fallback_test.lua','tests/8126_sunrise_sky_test.lua','tools/baselines/8.1.26-runtime-sha256.json']:
 ck((R/f).exists(),f+' exists')
notes=(R/'RELEASE-NOTES-8.1.26.md').read_text()
ck('61 settings' in notes,'release notes document 61-setting audit')
ck('does not reduce particle counts' in notes,'release notes preserve quality contract')
f=sum(not v for v,_ in checks); print(f'8.1.26 package surface: {len(checks)-f}/{len(checks)} passed'); sys.exit(1 if f else 0)
