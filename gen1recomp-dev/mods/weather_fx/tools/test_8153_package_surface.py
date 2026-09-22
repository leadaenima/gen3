#!/usr/bin/env python3
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.53','manifest 8.1.53')
ck((R/'BASELINE').read_text().strip()=='8.1.53','BASELINE 8.1.53')
ck(not (R/'texluac.out').exists(),'no texluac.out compiler artifact')
for f in ['RELEASE-NOTES-8.1.53.md','WEATHER-FX-8.1.53-FINAL-AUDIT.md','tools/test_8153_cloud_sun_localization.py','tools/test_8153_performance_contract.py','tools/test_8153_runtime_delta.py','tools/test_8153_runtime_freeze.py','tools/test_8153_package_surface.py','tests/cloud_sun_localization_8153_test.lua','tools/baselines/8.1.52-runtime-sha256.json','tools/baselines/8.1.53-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
eng=(R/'lib/CelestialEngine.lua').read_text(); cin=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text(); wcl=(R/'lib/voxel_atmos/WorldCelestialLighting.lua').read_text()
ck('direct=direct*lerp(0.20,1,localT)' not in eng and 'World illumination is REGIONAL' in eng,'local player cloud ray cannot drive shared world direct light')
ck('CinematicAtmos._regionalCloudCoverage' in cin and 'E.observeCloudField(tr,regional)' in cin,'regional cloud coverage observer present')
ck('Match the same four macro lobes used by CinematicAtmos cloud occlusion' in wcl,'spatial terrain cloud-body mask present')
print(f'8.1.53 package surface: {sum(checks)}/{len(checks)} passed'); sys.exit(0 if all(checks) else 1)
