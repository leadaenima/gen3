#!/usr/bin/env python3
"""Run only the 8.1.18 frozen-baseline regression wall."""
from pathlib import Path
import subprocess,sys,time
R=Path(__file__).resolve().parents[1]
cmds=[
 ['python3','tools/test_8118_runtime_freeze.py'],
 ['python3','tools/test_8118_manifest_freeze.py'],
 ['python3','tools/test_8118_semantic_snapshot.py'],
 ['python3','tools/test_8118_config_quality_snapshot.py'],
 ['texlua','tests/8118_weather_catalog_exhaustive_test.lua'],
 ['texlua','tests/8118_celestial_stress_test.lua'],
 ['texlua','tests/8118_wind_stress_test.lua'],
 ['texlua','tests/8118_building_light_stress_test.lua'],
 ['texlua','tests/8118_night_scheduler_stress_test.lua'],
 ['texlua','tests/8118_weather_off_crossmodule_test.lua'],
 ['python3','tools/test_8118_package_surface.py'],
]
start=time.time(); failed=[]
for c in cmds:
 print('\n=====',' '.join(c),'=====',flush=True)
 r=subprocess.run(c,cwd=R)
 if r.returncode: failed.append((' '.join(c),r.returncode))
print(f'\n8.1.18 regression wall completed in {time.time()-start:.1f}s; gates={len(cmds)}; failures={len(failed)}')
for n,rc in failed: print('FAIL',rc,n)
sys.exit(1 if failed else 0)
