#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];c=[]
def ck(x,m):c.append((bool(x),m));print(('PASS ' if x else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text());ck(man.get('version')=='8.1.24','manifest 8.1.24')
for f in ['RELEASE-NOTES-8.1.24.md','tools/test_8124_runtime_freeze.py','tools/test_8124_zero_quality_perf.py','tests/8124_night_geometry_equivalence_test.lua','tools/baselines/8.1.24-runtime-sha256.json']:
 ck((R/f).exists(),'shipped '+f)
ck((R/'BASELINE').read_text().strip()=='8.1.24','BASELINE marker 8.1.24')
ck('zero-quality-loss' in (R/'BASELINE.md').read_text().lower(),'baseline documents zero-quality-loss contract')
ck('RAIN_MAX remains 12,000' in (R/'RELEASE-NOTES-8.1.24.md').read_text(),'release notes preserve rain population')
f=sum(not v for v,_ in c);print(f'8.1.24 package surface: {len(c)-f}/{len(c)} passed');raise SystemExit(1 if f else 0)
