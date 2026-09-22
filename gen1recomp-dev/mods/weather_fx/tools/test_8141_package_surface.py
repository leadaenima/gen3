#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.41','manifest 8.1.41')
ck((R/'BASELINE').read_text().strip()=='8.1.41','BASELINE marker 8.1.41')
for f in ['RELEASE-NOTES-8.1.41.md','tests/storm_front_reachability_8141_test.lua','tests/storm_front_scale_render_8141_test.lua','tools/test_8141_runtime_delta.py','tools/test_8141_package_surface.py','tools/test_8141_storm_front_contract.py','tools/baselines/8.1.40-runtime-sha256.json','tools/baselines/8.1.41-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
sc=(R/'lib/StormCells.lua').read_text();dw=(R/'lib/DistantWeather.lua').read_text();ca=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text();rn=(R/'RELEASE-NOTES-8.1.41.md').read_text()
ck(all(x in sc for x in ['"cell"','"regional"','"broad"','"synoptic"','footprintMetric','edgeGap','speedMul','maxShift']),'size classes + leading-edge/interception engine shipped')
ck('.75,4.10' in sc and '.90+ws*2.20' in sc,'slow bounded storm translation shipped')
ck('ellipseRadius' in dw and 'insideDepth' in dw and '1-.48*smooth' in dw,'contact-aware nonzero cloud handoff shipped')
ck('bankX' in dw and 'bankZ' in dw and 'shaftHandoff' in dw,'leading-edge anchor + precipitation handoff shipped')
ck('physicalCross' in ca and 'far*2.25' in ca and 'sizeClass=="synoptic"' in ca,'world-scale shared cloud-bank presentation shipped')
ck('5.5–18.5' in rn and 'leading edge' in rn.lower() and 'physically intercept' in rn.lower(),'player-visible speed/reachability behavior documented')
ck('8.1.40' in rn and 'VOID-water' in rn,'8.1.40 water baseline preservation documented')
failed=sum(not v for v,_ in checks);print(f'8.1.41 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
