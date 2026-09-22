#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m))
bad=[]
for p in R.rglob('*'):
 if not p.is_file(): continue
 rel=p.relative_to(R).as_posix()
 if any(x in rel for x in ('__pycache__/','.pytest_cache/','.DS_Store')) or rel.endswith(('.pyc','.pyo','.bak','~')): bad.append(rel)
ck(not bad,'no cache/backup junk in package tree')
mods=list((R/'lib').rglob('*.lua')); freeze=json.loads((R/'tools/baselines/8.1.20-runtime-sha256.json').read_text())['files']
ck(all(p.relative_to(R).as_posix() in freeze for p in mods),'every runtime lib Lua module is in 8.1.20 byte-freeze baseline')
ck((R/'tools/test_8120_weather_duration.py').exists(),'weather-duration contract test shipped')
ck((R/'tests/weather_shadow_engine_test.lua').exists(),'8.1.19 owned shadow runtime test retained')
run=(R/'tools/run_all.py').read_text()
for n in ['test_8120_runtime_freeze.py','test_8120_weather_duration.py','test_8120_package_surface.py','test_8119_shadow_engine.py','weather_shadow_engine_test.lua']:
 ck(n in run,'run_all executes '+n)
man=json.loads((R/'manifest.json').read_text()); ck(man.get('version')=='8.1.20','manifest is 8.1.20')
ck('weather-duration' in man.get('baselineNote','').lower(),'manifest names weather-duration delta')
failed=[m for v,m in checks if not v]
print(f'8.1.20 package/test surface: {len(checks)-len(failed)}/{len(checks)} passed; runtime modules={len(mods)}')
for m in failed: print('FAIL',m)
sys.exit(1 if failed else 0)
