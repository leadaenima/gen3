#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.56','manifest 8.1.56')
ck((R/'BASELINE').read_text().strip()=='8.1.56','BASELINE 8.1.56')
for f in ['RELEASE-NOTES-8.1.56.md','tools/test_8156_runtime_delta.py','tools/test_8156_runtime_freeze.py','tools/test_8156_package_surface.py','tools/test_8156_battle_precip_continuity.py','tests/battle_precip_continuity_8156_test.lua','tools/baselines/8.1.56-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
print(f'8.1.56 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
