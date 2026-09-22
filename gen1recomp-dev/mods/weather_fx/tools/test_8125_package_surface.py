#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]
man=json.loads((R/'manifest.json').read_text()); checks=[]
def ck(v,m): checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
ck(man.get('version')=='8.1.25','manifest 8.1.25')
for f in ['RELEASE-NOTES-8.1.25.md','tools/test_8125_runtime_freeze.py','tools/test_8125_constellation_polish.py','tools/baselines/8.1.25-runtime-sha256.json']:
 ck((R/f).exists(),f+' exists')
ck((R/'BASELINE').read_text().strip()=='8.1.25','BASELINE marker 8.1.25')
ck('same BuildingLight star-scale response as ordinary stars' in (R/'RELEASE-NOTES-8.1.25.md').read_text(),'release notes preserve building-light parity')
f=sum(not v for v,_ in checks);print(f'8.1.25 package surface: {len(checks)-f}/{len(checks)} passed');raise SystemExit(1 if f else 0)
