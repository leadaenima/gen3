#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];c=[]
def ck(v,m): c.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text());ck(man.get('version')=='8.1.58','manifest 8.1.58');ck((R/'BASELINE').read_text().strip()=='8.1.58','BASELINE 8.1.58')
for f in ['RELEASE-NOTES-8.1.58.md','tools/test_8158_runtime_delta.py','tools/test_8158_runtime_freeze.py','tools/test_8158_package_surface.py','tools/test_8158_tornado_contract.py','tests/tornado_2d_relocation_8158_test.lua','tests/funnel_relocation_choreography_8158_test.lua','tests/funnel_blackout_framebuffer_8158_test.lua','tests/tornado_relocation_8158_test.lua','tests/tornado_waterspout_8158_test.lua','tools/baselines/8.1.58-runtime-sha256.json']:
 ck((R/f).exists(),f+' present')
print(f'8.1.58 package surface: {sum(c)}/{len(c)} passed');sys.exit(0 if all(c) else 1)
