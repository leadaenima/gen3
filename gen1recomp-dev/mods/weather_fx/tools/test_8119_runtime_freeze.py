#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
R=Path(__file__).resolve().parents[1]
old=json.loads((R/'tools/baselines/8.1.17-runtime-sha256.json').read_text())['files']
newdoc=json.loads((R/'tools/baselines/8.1.19-runtime-sha256.json').read_text()); new=newdoc['files']
allowed={'lib/DramalessAtmos.lua','lib/WeatherShadowMap.lua'}
fails=[]; passed=0

def runtime_files():
 out=[]
 for p in sorted(R.rglob('*')):
  if not p.is_file(): continue
  rel=p.relative_to(R).as_posix()
  if rel in ('main.lua','config.lua') or rel.startswith('assets/') or rel.startswith('compat/') or (rel.startswith('lib/') and not rel.endswith('.md')): out.append(rel)
 return out
actual=runtime_files()
if actual!=sorted(new): fails.append('runtime path set differs from 8.1.19 frozen baseline')
else: passed+=1
for rel,exp in new.items():
 raw=(R/rel).read_bytes(); h=hashlib.sha256(raw).hexdigest()
 if h!=exp['sha256'] or len(raw)!=exp['size']: fails.append(f'{rel}: 8.1.19 runtime drift')
 else: passed+=1
# Prove the release changed only the requested shadow integration from 8.1.17/8.1.18 runtime.
delta={p for p in set(old)|set(new) if old.get(p)!=new.get(p)}
if delta!=allowed: fails.append('unexpected intentional runtime delta: '+', '.join(sorted(delta)))
else: passed+=1
print(f'8.1.19 runtime freeze: {passed}/{len(new)+2} passed; files={len(new)}; delta={sorted(delta)}')
for f in fails: print('FAIL',f)
sys.exit(1 if fails else 0)
