#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]
exp=(R/'tools/baselines/8.1.17-config-quality-snapshot.txt').read_text().splitlines()
p=subprocess.run(['texlua',str(R/'tools/8118_config_quality_dump.lua')],cwd=R,text=True,capture_output=True)
if p.returncode: print(p.stdout,p.stderr); sys.exit(p.returncode)
act=p.stdout.splitlines(); bad=[]
if len(act)!=len(exp): bad.append(f'line count {len(act)} != {len(exp)}')
for i,(a,e) in enumerate(zip(act,exp),1):
 if a!=e:
  bad.append(f'{i}: {a} != {e}')
  if len(bad)>=25: break
print(f'8.1.17 config/quality semantic freeze: {len(exp)-len(bad)}/{len(exp)} baseline observations retained')
for b in bad: print('FAIL',b)
sys.exit(1 if bad else 0)
