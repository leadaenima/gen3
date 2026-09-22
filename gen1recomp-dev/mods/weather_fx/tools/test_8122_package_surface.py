#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
bad=[]
for p in R.rglob('*'):
 if not p.is_file(): continue
 rel=p.relative_to(R).as_posix()
 if any(x in rel for x in ('__pycache__/','.pytest_cache/','.DS_Store')) or rel.endswith(('.pyc','.pyo','.bak','~')): bad.append(rel)
ck(not bad,'no cache/backup junk')
man=json.loads((R/'manifest.json').read_text()); current=man.get('version','8.1.22')
freeze_path=R/f'tools/baselines/{current}-runtime-sha256.json'
if not freeze_path.exists(): freeze_path=R/'tools/baselines/8.1.22-runtime-sha256.json'
freeze=json.loads(freeze_path.read_text())['files']
mods=list((R/'lib').rglob('*.lua'));ck(all(p.relative_to(R).as_posix() in freeze for p in mods),'all runtime Lua modules frozen in selected baseline')
for f in ['lib/WeatherWorldSpace.lua','lib/StormCells.lua','tests/weather_world_space_test.lua','tests/storm_cell_lifecycle_test.lua','tests/storm_cross_map_seam_test.lua','tools/test_8122_world_weather_contract.py','tools/test_8122_runtime_freeze.py']:
 ck((R/f).exists(),'shipped '+f)
run=(R/'tools/run_all.py').read_text()
for n in ['test_8122_world_weather_contract.py','weather_world_space_test.lua','storm_cell_lifecycle_test.lua','storm_cross_map_seam_test.lua','test_8121_player_controls.py','test_8120_weather_duration.py','weather_shadow_engine_test.lua']:
 ck(n in run,'run_all executes '+n)
ver=tuple(int(x) for x in man.get('version','0.0.0').split('.')[:3]);ck(ver>=(8,1,22),'manifest retains 8.1.22+ storm-cell generation');ck('storm' in man.get('baselineNote','').lower() or ver>(8,1,22),'manifest/newer baseline retains storm-cell generation')
failed=[m for v,m in checks if not v]
print(f'8.1.22 package surface: {len(checks)-len(failed)}/{len(checks)} passed')
sys.exit(1 if failed else 0)
