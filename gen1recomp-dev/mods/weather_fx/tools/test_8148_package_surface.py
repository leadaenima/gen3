#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text()); ck(man.get('version')=='8.1.48','manifest 8.1.48'); ck((R/'BASELINE').read_text().strip()=='8.1.48','BASELINE 8.1.48')
for f in ['RELEASE-NOTES-8.1.48.md','tools/test_8148_compile_repair.py','tools/test_8148_runtime_delta.py','tools/test_8148_runtime_freeze.py','tools/test_8148_package_surface.py','tools/baselines/8.1.47-runtime-sha256.json','tools/baselines/8.1.48-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
rn=(R/'RELEASE-NOTES-8.1.48.md').read_text(); ck('comment prefix' in rn and 'only `lib/EngineRuntime.lua`' in rn,'root cause and one-file runtime delta documented'); ck('No graphics' in rn,'zero-quality-loss preservation documented')
print(f'8.1.48 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
