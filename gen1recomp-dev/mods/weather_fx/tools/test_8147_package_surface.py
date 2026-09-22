#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.47','manifest 8.1.47'); ck((R/'BASELINE').read_text().strip()=='8.1.47','BASELINE marker 8.1.47')
for f in ['RELEASE-NOTES-8.1.47.md','PERFORMANCE-AUDIT-8.1.47.md','tests/flat_voxel_prune_8147_test.lua','tools/test_8147_flat_voxel_prune_contract.py','tools/test_8147_package_surface.py','tools/test_8147_runtime_delta.py','tools/test_8147_runtime_freeze.py','tools/baselines/8.1.46-runtime-sha256.json','tools/baselines/8.1.47-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
rn=(R/'RELEASE-NOTES-8.1.47.md').read_text()
ck('zero' in rn.lower() and 'quality' in rn.lower() and 'No particle ceiling' in rn,'zero-visible-quality-loss preservation documented')
ck('21,760' in rn and '3,648' in rn,'old-vs-new output equivalence evidence documented')
ck('WorldStreamer' in rn and 'GPUWeatherEngine' in rn and 'LightProbeGrid' in rn and 'SurfaceVisuals' in rn,'four advisory passes documented')
ck('75' in rn and 'materializes' in rn and 'VolumetricWeather.cells()' in rn,'lazy volumetric compatibility contract documented')
ck('PredictiveBudget' in rn and 'WorkloadRouter' in rn and 'AUTO' in rn,'manual QUALITY bookkeeping sleep documented')
failed=sum(not v for v,_ in checks); print(f'8.1.47 package surface: {len(checks)-failed}/{len(checks)} passed'); sys.exit(1 if failed else 0)
