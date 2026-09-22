#!/usr/bin/env python3
"""Regression wall for package cleanliness and test coverage surface."""
from pathlib import Path
import json,re,sys,zipfile
R=Path(__file__).resolve().parents[1]
checks=[]
def ck(v,m): checks.append((bool(v),m));
# no junk/backups/caches shipped
bad=[]
for p in R.rglob('*'):
 if not p.is_file(): continue
 rel=p.relative_to(R).as_posix()
 if any(x in rel for x in ('__pycache__/','.pytest_cache/','.DS_Store')) or rel.endswith(('.pyc','.pyo','.bak','~')): bad.append(rel)
ck(not bad,'no cache/backup junk in package tree')
# Runtime modules all have syntax guard coverage simply by being .lua under lib, and freeze baseline coverage.
mods=[p for p in (R/'lib').rglob('*.lua')]
freeze=json.loads((R/'tools/baselines/8.1.17-runtime-sha256.json').read_text())['files']
ck(len(mods)>=110,'at least 110 runtime Lua modules inventoried')
ck(all(p.relative_to(R).as_posix() in freeze for p in mods),'every runtime lib Lua module is in 8.1.17 byte-freeze baseline')
# All current tests are actual files and mass-wall tests are installed.
tests=list((R/'tests').glob('*_test.lua')); pytests=list((R/'tools').glob('test_*.py'))
ck(len(tests)>=95,'at least 95 Lua regression tests shipped')
ck(len(pytests)>=45,'at least 45 Python regression/audit tests shipped')
required=['8118_weather_catalog_exhaustive_test.lua','8118_celestial_stress_test.lua','8118_wind_stress_test.lua','8118_building_light_stress_test.lua','8118_night_scheduler_stress_test.lua','8118_weather_off_crossmodule_test.lua']
for n in required: ck((R/'tests'/n).exists(),'mass regression test present: '+n)
for n in ['test_8118_runtime_freeze.py','test_8118_manifest_freeze.py','test_8118_semantic_snapshot.py','test_8118_config_quality_snapshot.py']:
 ck((R/'tools'/n).exists(),'baseline freeze test present: '+n)
# New tests are wired into run_all, otherwise decorative tests are easy to forget.
run=(R/'tools/run_all.py').read_text()
for n in required: ck(n in run,'run_all executes '+n)
for n in ['test_8118_runtime_freeze.py','test_8118_manifest_freeze.py','test_8118_semantic_snapshot.py','test_8118_config_quality_snapshot.py','test_8118_package_surface.py']:
 ck(n in run,'run_all executes '+n)
# Version/meta lineage only; behavior is separately frozen against 8.1.17.
man=json.loads((R/'manifest.json').read_text()); ck(tuple(map(int,man['version'].split('.')[:3]))>=(8,1,18),'test-hardening package version 8.1.18+')
ck('8.1.17' in man.get('baselineNote',''),'manifest explicitly names 8.1.17 runtime baseline')
failed=[m for v,m in checks if not v]
print(f'8.1.18 package/test surface: {len(checks)-len(failed)}/{len(checks)} passed; Lua tests={len(tests)}, Python tests={len(pytests)}, runtime modules={len(mods)}')
for m in failed: print('FAIL',m)
sys.exit(1 if failed else 0)
