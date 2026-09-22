#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.40','manifest 8.1.40')
ck((R/'BASELINE').read_text().strip()=='8.1.40','BASELINE marker 8.1.40')
for f in ['RELEASE-NOTES-8.1.40.md','tools/test_8140_void_underlay.py','tools/test_8140_runtime_delta.py','tools/test_8140_package_surface.py','tools/baselines/8.1.39-runtime-sha256.json','tools/baselines/8.1.40-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
da=(R/'lib/DramalessAtmos.lua').read_text();rn=(R/'RELEASE-NOTES-8.1.40.md').read_text()
ck('wrapHostVoidUnderlay' in da and 'preflightVoidOwnership' in da,'exclusive underlay ownership implementation shipped')
ck('CW3.prepare(nil)' in da and '_wxVoidPreflightRepl' in da,'renderer-preflight result is cached and reused')
ck('return origDraw(...)' in da and 'waterStyleEnabled()' in da,'native fail-open path preserved')
ck('drawFootprints' in da and 'safety footprints' in rn,'loaded-map footprint safety is preserved/documented')
ck('WATER STYLE = ORIGINAL' in rn and 'fail' in rn.lower(),'ORIGINAL/failure handoff documented')
ck('8.1.39' in rn and '8.1.38' in rn,'prior universal ownership and living-pond lineage documented')
failed=sum(not v for v,_ in checks);print(f'8.1.40 package surface: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
