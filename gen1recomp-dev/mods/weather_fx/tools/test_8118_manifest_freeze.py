#!/usr/bin/env python3
"""Ensure a test-hardening release does not silently change host/dependency/runtime metadata."""
from pathlib import Path
import json, sys
R=Path(__file__).resolve().parents[1]
cur=json.loads((R/'manifest.json').read_text())
exp=json.loads((R/'tools/baselines/8.1.17-manifest-behavior.json').read_text())
ver=cur.pop('version',None); cur.pop('baselineNote',None)
fails=[]; checks=0
for k in sorted(set(cur)|set(exp)):
    checks+=1
    if cur.get(k)!=exp.get(k): fails.append(f'{k}: {cur.get(k)!r} != approved {exp.get(k)!r}')
checks+=1
if not ver or tuple(map(int,ver.split('.')[:3])) < (8,1,17): fails.append('version lineage regressed')
print(f'8.1.17 manifest behavior freeze: {checks-len(fails)}/{checks} passed')
for f in fails: print('FAIL',f)
sys.exit(1 if fails else 0)
