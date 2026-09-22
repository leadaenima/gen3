#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.30','manifest 8.1.30')
ck((R/'BASELINE').read_text().strip()=='8.1.30','BASELINE marker 8.1.30')
for f in ['RELEASE-NOTES-8.1.30.md','lib/voxel_atmos/ConnectedWater3D.lua','tests/ice_realism_8130_test.lua','tools/test_8130_runtime_delta.py']:
    ck((R/f).exists(),f+' ships')
r=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text()
ck('size=isIce and 128' in r and 'iceNoise' in r,'large-scale procedural ice material ships')
ck('iceTextureForStage' in r and '_skinDraws' in r,'progressive skim-ice stages ship')
ck('192,"ice"' in r,'ice UV scale widened without changing liquid mapping')
ck('movement.collision' not in r,'presentation upgrade does not broaden gameplay collision hooks')
failed=sum(not v for v,_ in checks);print(f'8.1.30 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
