#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.54','manifest 8.1.54')
ck((R/'BASELINE').read_text().strip()=='8.1.54','BASELINE 8.1.54')
ck(not (R/'texluac.out').exists(),'no texluac.out compiler artifact')
for f in ['RELEASE-NOTES-8.1.54.md','PERFORMANCE-AUDIT-8.1.54.md','WEATHER-FX-8.1.54-FINAL-AUDIT.md','tools/test_8154_performance_contract.py','tools/test_8154_runtime_delta.py','tools/test_8154_runtime_freeze.py','tools/test_8154_package_surface.py','tests/near_precip_virtualization_8154_test.lua','tests/max_precip_virtualization_8154_test.lua','tools/baselines/8.1.53-runtime-sha256.json','tools/baselines/8.1.54-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text(); pp=(R/'lib/ProceduralPrecipField.lua').read_text(); ps=(R/'lib/ProceduralSnowField.lua').read_text()
ck('rain.simActive=min(wantRain,96)' in wp and 'rain.gpuActive=wantRain' in wp,'rain complete visual GPU ownership with <=96 CPU probes')
ck('wantSnowSim=min(wantSnow,96)' in wp and 'gpuSnow=wantSnow' in wp,'snow complete visual GPU ownership with <=96 CPU probes')
ck('grain.simTarget[kind]=0' in wp and 'grain.gpuTarget[kind]=logical' in wp,'hail/sand/ash complete visual GPU ownership')
ck('function WP.snowGroundCollisionEnabled() return false end' in wp,'snow ground collision explicitly disabled')
ck('function P.canVirtualize()' in pp and 'state.proven==true' in pp,'procedural precipitation requires real driver proof')
ck('complete' in ps and 'visible snow population' in ps,'procedural snow full-visual ownership documented')
print(f'8.1.54 package surface: {sum(checks)}/{len(checks)} passed'); sys.exit(0 if all(checks) else 1)
