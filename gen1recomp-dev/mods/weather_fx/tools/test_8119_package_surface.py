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
mods=list((R/'lib').rglob('*.lua')); freeze=json.loads((R/'tools/baselines/8.1.19-runtime-sha256.json').read_text())['files']
ck(len(mods)>=111,'runtime Lua inventory includes owned shadow module')
ck(all(p.relative_to(R).as_posix() in freeze for p in mods),'every runtime lib Lua module is in 8.1.19 byte-freeze baseline')
tests=list((R/'tests').glob('*_test.lua')); pytests=list((R/'tools').glob('test_*.py'))
ck((R/'tests/weather_shadow_engine_test.lua').exists(),'owned shadow runtime test shipped')
ck((R/'tests/shadow_projection_monotonic_test.lua').exists(),'shadow projection stress test shipped')
required=['8118_weather_catalog_exhaustive_test.lua','8118_celestial_stress_test.lua','8118_wind_stress_test.lua','8118_building_light_stress_test.lua','8118_night_scheduler_stress_test.lua','8118_weather_off_crossmodule_test.lua']
for n in required: ck((R/'tests'/n).exists(),'8.1.18 mass regression retained: '+n)
run=(R/'tools/run_all.py').read_text()
for n in required: ck(n in run,'run_all retains '+n)
for n in ['test_8119_runtime_freeze.py','test_8119_shadow_engine.py','weather_shadow_engine_test.lua','shadow_projection_monotonic_test.lua','test_8119_package_surface.py']:
 ck(n in run,'run_all executes '+n)
man=json.loads((R/'manifest.json').read_text()); ck(man.get('version')=='8.1.19','manifest is 8.1.19')
ck('owned shadow-engine' in man.get('baselineNote','').lower() or 'owned shadow' in man.get('baselineNote','').lower(),'manifest names owned shadow delta')
failed=[m for v,m in checks if not v]
print(f'8.1.19 package/test surface: {len(checks)-len(failed)}/{len(checks)} passed; Lua tests={len(tests)}, Python tests={len(pytests)}, runtime modules={len(mods)}')
for m in failed: print('FAIL',m)
sys.exit(1 if failed else 0)
