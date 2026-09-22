#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];c=[]
def ck(v,m): c.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.61','manifest 8.1.61')
ck((R/'BASELINE').read_text().strip()=='8.1.61','BASELINE 8.1.61')
for f in ['RELEASE-NOTES-8.1.61.md','tests/tornado_real_transfer_8161_test.lua','tools/test_8161_runtime_delta.py','tools/test_8161_runtime_freeze.py','tools/test_8161_package_surface.py','tools/test_8161_tornado_transfer_contract.py','tools/baselines/8.1.61-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
ck('Tornado Real Map Transfer' in (R/'CHANGELOG.md').read_text()[:600],'changelog 8.1.61 entry')
ck('Tornado Real Map Transfer' in (R/'README.md').read_text()[:600],'README 8.1.61 entry')
print(f'8.1.61 package surface: {sum(c)}/{len(c)} passed')
sys.exit(0 if all(c) else 1)
