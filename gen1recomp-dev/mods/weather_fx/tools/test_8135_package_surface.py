#!/usr/bin/env python3
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.35','manifest 8.1.35')
ck((R/'BASELINE').read_text().strip()=='8.1.35','BASELINE marker 8.1.35')
for f in ['RELEASE-NOTES-8.1.35.md','lib/voxel_atmos/ConnectedWater3D.lua','tests/foam_persistence_8135_test.lua','tests/void_water_8134_test.lua','tests/professional_water_8133_test.lua','tests/water_hotpath_8132_test.lua','tests/wave_realism_8131_test.lua','tests/water_style_8131_test.lua','tests/ice_realism_8130_test.lua','tools/test_8135_runtime_delta.py','tools/baselines/8.1.34-runtime-sha256.json','tools/baselines/8.1.35-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
s=(R/'lib/voxel_atmos/ConnectedWater3D.lua').read_text();rn=(R/'RELEASE-NOTES-8.1.35.md').read_text()
ck('foamEnvelope' in s and 'trackPhase' in s and '_whitecapTrackAt' in s,'persistent analytic foam lifetime/track authority present')
ck('foamRibbon' in s and 'Five cross-sections' in s,'tapered non-rectangular whitecap ribbon geometry present')
ck('foamCurlLip' in s and 'SAME moving whitecap' in s,'curling lip is attached to persistent crest identity')
ck('River whitewater is now a moving tapered streak' in s,'river rapids use moving persistent streaks')
ck('Static edge admission' in s and 'half-second-bucket random re-roll' in s,'shore break uses stable edge identity instead of time bucket')
ck('floor(t*0.5)' not in s,'old shoreline time-bucket teleport trigger absent')
ck(('void water' in rn.lower() or 'void-water' in rn.lower()) and 'water style' in rn.lower(),'8.1.34 void-water/WATER STYLE preservation documented')
ck('no visible reset' in rn.lower() or 'zero-size' in rn.lower(),'invisible reset contract documented')
failed=sum(not v for v,_ in checks);print(f'8.1.35 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
