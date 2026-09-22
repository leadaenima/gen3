#!/usr/bin/env python3
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.34','manifest 8.1.34')
ck((R/'BASELINE').read_text().strip()=='8.1.34','BASELINE marker 8.1.34')
for f in ['RELEASE-NOTES-8.1.34.md','lib/voxel_atmos/ConnectedWater3D.lua','lib/ConnectedWater.lua','tests/void_water_8134_test.lua','tests/professional_water_8133_test.lua','tests/water_hotpath_8132_test.lua','tests/wave_realism_8131_test.lua','tests/water_style_8131_test.lua','tests/ice_realism_8130_test.lua','tools/test_8134_runtime_delta.py','tools/baselines/8.1.33-runtime-sha256.json','tools/baselines/8.1.34-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
s=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text();h=(R/'lib/ConnectedWater.lua').read_text();d=(R/'lib/DramalessAtmos.lua').read_text();rn=(R/'RELEASE-NOTES-8.1.34.md').read_text()
ck('src.render.TileRenderer' in h and 'voidWaterMode' in h,'Gen1Recomp live VOID FILL authority hook present')
ck('VOID_RING_CELLS=6' in h and '96px' in h,'exact Voxel Realism three-block / 96px apron contract present')
ck('visualOnly=true' in h and 'voidWater=true' in h and 'W.renderBodies' in h,'void sea is visual-only and published separately from gameplay bodies')
ck('bodyBy[cellKey(c.gx,c.gz)]=b' in h and 'voidBodies[1]=b' in h,'cartridge bodyByCell and visual void-body ownership stay separated')
ck('renderBodies(CW)' in s and '#bodies>0' in s,'3D renderer can own a void-only water list')
ck('weatherFxWaterEnabled' in d and 'CW3.setEnabled(false)' in d and 'return origWater(draws,cast,...)' in d,'WATER STYLE ORIGINAL releases authored and void water to host')
ck('void=' in h and 'voidWaterMode(state)' in h,'VOID FILL mode participates in live topology invalidation')
ck('never gameplay water' in rn.lower() or 'never enters cartridge' in rn.lower(),'presentation-only gameplay safety documented')
failed=sum(not v for v,_ in checks);print(f'8.1.34 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
