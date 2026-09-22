#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.46','manifest 8.1.46');ck((R/'BASELINE').read_text().strip()=='8.1.46','BASELINE marker 8.1.46')
for f in ['RELEASE-NOTES-8.1.46.md','tests/voxel_nexus_water_continuity_8146_test.lua','tests/quality_presets_8146_test.lua','tests/constellation_building_direction_8146_test.lua','tools/test_8146_voxel_nexus_continuity_contract.py','tools/test_8146_package_surface.py','tools/test_8146_runtime_delta.py','tools/test_8146_runtime_freeze.py','tools/baselines/8.1.45-runtime-sha256.json','tools/baselines/8.1.46-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
rn=(R/'RELEASE-NOTES-8.1.46.md').read_text()
ck('SKY-only' in rn and 'Fresnel' in rn and '96px' in rn,'near/far material continuity contract documented')
ck('no `Voxel3D.beginWater`' in rn and 'screen-space reflection ray march' in rn,'VOID performance preservation documented')
ck('8.1.45' in rn and 'public battle art' in rn.lower(),'prior Nexus + public Battle Art ownership explicitly preserved')
ck('QUALITY PRESET' in rn and 'AUTO PERFORMANCE' in rn and 'POTATO' in rn and 'TEXTURE DETAIL' in rn,'whole-mod low-end quality controls documented')
ck('monotonically' in rn and 'fake town-centre/corner' in rn and '8,507' in rn,'constellation building-direction repair documented')
failed=sum(not v for v,_ in checks);print(f'8.1.46 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
