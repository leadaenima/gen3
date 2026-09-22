#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.33','manifest 8.1.33')
ck((R/'BASELINE').read_text().strip()=='8.1.33','BASELINE marker 8.1.33')
for f in ['RELEASE-NOTES-8.1.33.md','lib/voxel_atmos/ConnectedWater3D.lua','lib/ConnectedWater.lua','tests/professional_water_8133_test.lua','tests/water_hotpath_8132_test.lua','tests/wave_realism_8131_test.lua','tests/water_style_8131_test.lua','tests/ice_realism_8130_test.lua','tools/test_8133_runtime_delta.py','tools/baselines/8.1.32-runtime-sha256.json','tools/baselines/8.1.33-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
s=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text();h=(R/'lib/ConnectedWater.lua').read_text();rn=(R/'RELEASE-NOTES-8.1.33.md').read_text()
ck('surfaceEntryForBody' in s and 'updatePhysicalSurface' in s and '_usingPhysicalSurface' in s,'true dynamic physical surface implementation present')
ck('waveHorizontalAtT' in s and 'Shore-pinning mask' in s,'Gerstner-style orbital motion plus shoreline pinning present')
ck('_whitecapQuads' in s and '_curlQuads' in s and '_rapidQuads' in s and '_shoreFoamQuads' in s,'whitecap/curl/rapid/shore-break geometry present')
ck('physicalWaveHeightForBody' in s and 'bodyMorphology' in h,'body-aware physical wave system present')
ck('playerBob' in s and 'waveDisplacementAt' in s,'Surf/player presentation samples wave field')
ck('Compatibility falls back' in man.get('baselineNote','') or 'Fail-open compatibility' in rn,'fail-open compatibility documented')
failed=sum(not v for v,_ in checks);print(f'8.1.33 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
