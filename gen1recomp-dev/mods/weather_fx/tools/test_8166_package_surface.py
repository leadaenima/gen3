#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];m=json.loads((R/'manifest.json').read_text());checks=[]
def ck(v,msg): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck(m.get('version')=='8.1.66','manifest 8.1.66');ck((R/'BASELINE').read_text().strip()=='8.1.66','BASELINE 8.1.66')
for rel in ['RELEASE-NOTES-8.1.66.md','WEATHER-FX-8.1.66-FINAL-AUDIT.md','lib/SnowSurfacePaint.lua','tests/snow_surface_repaint_8166_test.lua','tests/snow_exact_tree_hull_8166_test.lua','tools/test_8166_snow_surface_repaint_contract.py','tools/test_8166_voxel_nexus_host_contract.py','tools/test_8166_runtime_delta.py','tools/test_8166_runtime_freeze.py','tools/test_8166_package_surface.py','tools/baselines/8.1.66-runtime-sha256.json']:
 ck((R/rel).is_file(),rel+' present')
print(f'8.1.66 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
