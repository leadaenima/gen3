#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];m=json.loads((R/'manifest.json').read_text());checks=[]
def ck(v,msg): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+msg)
ck(m.get('version')=='8.1.67','manifest 8.1.67');ck((R/'BASELINE').read_text().strip()=='8.1.67','BASELINE 8.1.67')
for rel in [
 'RELEASE-NOTES-8.1.67.md','WEATHER-FX-8.1.67-FINAL-AUDIT.md','WEATHER-FX-8.1.67-FINAL-QUALIFICATION.md',
 'lib/SnowSurfacePaint.lua','tests/tornado_2d_frequency_8167_test.lua','tests/celestial_2d_worldlock_8167_test.lua',
 'tests/celestial_presentation_setting_8167_test.lua','tests/snow_live_surface_alignment_8167_test.lua',
 'tools/test_8167_contract.py','tools/test_8167_voxel_nexus_contract.py','tools/test_8167_runtime_delta.py',
 'tools/test_8167_runtime_freeze.py','tools/test_8167_package_surface.py','tools/baselines/8.1.67-runtime-sha256.json']:
 ck((R/rel).is_file(),rel+' present')
print(f'8.1.67 package surface: {sum(checks)}/{len(checks)} passed');sys.exit(0 if all(checks) else 1)
