#!/usr/bin/env python3
"""High-detail semantic fingerprint of approved 8.1.17 behavior.

Unlike the byte freeze, this executes pure runtime modules and compares thousands of
observable values: weather definitions, celestial samples, horizon functions, lunar
phases, wind profiles/state evolution, and BuildingLight falloff.
"""
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]
exp=(R/'tools/baselines/8.1.17-semantic-snapshot.txt').read_text().splitlines()
p=subprocess.run(['texlua',str(R/'tools/8118_semantic_dump.lua')],cwd=R,text=True,capture_output=True)
if p.returncode:
    print(p.stdout); print(p.stderr); sys.exit(p.returncode)
act=p.stdout.splitlines(); fails=[]
if len(act)!=len(exp): fails.append(f'line count {len(act)} != baseline {len(exp)}')
for i,(a,e) in enumerate(zip(act,exp),1):
    if a!=e:
        fails.append(f'line {i}:\n  actual   {a}\n  baseline {e}')
        if len(fails)>=25: break
passed=min(len(act),len(exp))-sum(1 for a,e in zip(act,exp) if a!=e)
print(f'8.1.17 semantic snapshot: {passed}/{len(exp)} lines exact; total baseline observations={len(exp)}')
for f in fails: print('FAIL',f)
sys.exit(1 if fails else 0)
