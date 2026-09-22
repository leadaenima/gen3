#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];c=[]
def ck(v,n):c.append((bool(v),n));print(('PASS ' if v else 'FAIL ')+n)
man=json.loads((R/'manifest.json').read_text());ck(man.get('version')=='8.1.23','manifest 8.1.23')
for f in ['RELEASE-NOTES-8.1.23.md','tools/test_8123_runtime_freeze.py','tools/test_8123_fallback_controls.py','tests/8123_spatial_fallback_test.lua','tools/baselines/8.1.23-runtime-sha256.json']:ck((R/f).exists(),'shipped '+f)
run=(R/'tools/run_all.py').read_text();
for n in ['test_8123_runtime_freeze.py','test_8123_fallback_controls.py','8123_spatial_fallback_test.lua','test_8122_world_weather_contract.py','test_8121_player_controls.py','weather_shadow_engine_test.lua']:ck(n in run,'run_all executes '+n)
ck((R/'BASELINE').read_text().strip()=='8.1.23','BASELINE marker 8.1.23')
f=sum(not v for v,_ in c);print(f'8.1.23 package surface: {len(c)-f}/{len(c)} passed');raise SystemExit(1 if f else 0)
