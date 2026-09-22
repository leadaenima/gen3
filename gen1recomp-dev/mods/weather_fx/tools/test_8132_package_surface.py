#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.32','manifest 8.1.32')
ck((R/'BASELINE').read_text().strip()=='8.1.32','BASELINE marker 8.1.32')
for f in ['RELEASE-NOTES-8.1.32.md','lib/voxel_atmos/ConnectedWater3D.lua','lib/ConnectedWater.lua','tests/water_hotpath_8132_test.lua','tests/wave_realism_8131_test.lua','tests/water_style_8131_test.lua','tools/test_8132_runtime_delta.py','tools/baselines/8.1.31-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
s=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text();h=(R/'lib/ConnectedWater.lua').read_text()
ck('local CW=C._CW or req("ConnectedWater")' in s and 'local Water=C._Water or req("Water")' in s,'3D water module handles cached')
ck('local wx,wz=CW.windX,CW.windZ' in s and 'CW.sample()) or {}' in s,'direct wind path plus compatibility diagnostics fallback')
ck('reflectiveTranslation' in s and 'type(m)=="table" and #m>=16' in s,'structured reflective matrix reuse guarded by host representation')
ck('C._CW=nil;C._V3=nil;C._Mat4=nil' in s,'hot invalidate clears cached host handles')
ck('_Settings,_CelestialSim,_TimeOfDay,_WindEngine,_Microclimate' in h,'hydrosphere sibling dependencies cached')
ck('No quality reductions' in (R/'RELEASE-NOTES-8.1.32.md').read_text(),'zero-quality-loss release contract documented')
failed=sum(not v for v,_ in checks);print(f'8.1.32 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
