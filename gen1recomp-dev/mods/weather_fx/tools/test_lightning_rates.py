#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'lib/Types.lua').read_text()

# isolate each weather block by id and the following block delimiter
pairs=list(re.finditer(r'\bid\s*=\s*"([A-Z0-9_]+)"', s))
blocks={}
for i,m in enumerate(pairs):
    end=pairs[i+1].start() if i+1<len(pairs) else len(s)
    blocks[m.group(1)]=s[m.start():end]

def strike(wid):
    b=blocks[wid]
    m=re.search(r'\bstrike\s*=\s*([0-9.]+)', b)
    return float(m.group(1)) if m else 0.0

expected={'HEAVY_RAIN':6.0,'STORM':18.0,'PSYSTORM':84.0}
unchanged={'THUNDERSNOW':5.0,'DRAGONSTORM':7.0}
checks=[]
for wid,want in expected.items():
    got=strike(wid)
    checks.append((got==want,f'{wid} strike rate = {got:g}, expected {want:g}'))
    mean=60.0/got
    baseline=want/2.0
    oldmean=60.0/baseline
    checks.append((abs(mean-oldmean/2.0)<1e-12,f'{wid} mean interval is exactly halved ({mean:.6f}s)'))
for wid,want in unchanged.items():
    got=strike(wid)
    checks.append((got==want,f'{wid} unchanged at {got:g} strikes/min'))
got=strike('GALE')
checks.append((got==0.0,f'GALE has no lightning ({got:g} strikes/min)'))
# Explicitly lock the intended 100% relationship to 4.33.8 baseline.
baseline={'HEAVY_RAIN':3.0,'STORM':9.0,'PSYSTORM':42.0}
for wid,old in baseline.items():
    got=strike(wid)
    checks.append((got==old*2.0,f'{wid} is exactly +100% vs 4.33.8 ({old:g} -> {got:g})'))
failed=0
for ok,msg in checks:
    print(('PASS ' if ok else 'FAIL ')+msg)
    failed += 0 if ok else 1
print(f'\nlightning-rate tuning: {len(checks)-failed} passed, {failed} failed')
sys.exit(1 if failed else 0)
