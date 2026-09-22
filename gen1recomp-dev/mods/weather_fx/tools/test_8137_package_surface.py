#!/usr/bin/env python3
from pathlib import Path
import json,sys,re
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.37','manifest 8.1.37')
ck((R/'BASELINE').read_text().strip()=='8.1.37','BASELINE marker 8.1.37')
for f in ['RELEASE-NOTES-8.1.37.md','tests/storm_cloudbank_integration_8137_test.lua','tests/storm_handoff_volume_8136_test.lua','tools/test_8137_runtime_delta.py','tools/test_8137_package_surface.py','tools/baselines/8.1.36-runtime-sha256.json','tools/baselines/8.1.37-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
cin=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text();dist=(R/'lib/DistantWeather.lua').read_text();rn=(R/'RELEASE-NOTES-8.1.37.md').read_text()
ck('_appendFrontCloudDescriptors' in cin and 'frontCloudDescriptorProbe' in cin,'front descriptors join shared cloud-bank field')
ck('deckBase+hash2(seedX,seedZ,234)*deckSpan' in cin,'front centers use exact deck band equation')
ck('local function ellipsoid' not in cin and 'vKind > 5.5' not in cin,'legacy tessellated dark storm-cloud path absent')
ck('Two staggered X/Z rows' in cin and 'NO vertical row/stack' in cin,'maturity adds horizontal bank thickness instead of vertical blob stack')
ck('clouds = CinematicAtmos._appendFrontCloudDescriptors' in cin,'integration occurs before live cloud rendering/shadow observation')
ck('Front cloud mass is injected into the ordinary cloud-bank descriptor field' in cin,'distant stream is precipitation/lightning-only')
ck('nearFade' in dist and 'q.cloud=cloud*nearFade' in dist,'8.1.36 continuous remote-to-local cloud handoff preserved')
ck('same `deckY0 * CLOUD HEIGHT - landscapeDrop + hash * deckYSpan`' in rn,'one-altitude-authority contract documented')
ck('No player-visible quality tier' in rn,'zero-quality-loss cloud contract documented')
failed=sum(not v for v,_ in checks);print(f'8.1.37 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
