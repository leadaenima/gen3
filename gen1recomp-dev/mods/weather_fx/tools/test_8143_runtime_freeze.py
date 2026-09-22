#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]
doc=json.loads((R/'tools/baselines/8.1.43-runtime-sha256.json').read_text())
bad=[]
for rel,exp in doc['files'].items():
    p=R/rel
    if not p.exists(): print('FAIL missing '+rel);bad.append(rel);continue
    sha=hashlib.sha256(p.read_bytes()).hexdigest(); size=p.stat().st_size
    if sha!=exp['sha256'] or size!=exp['size']:
        print('FAIL changed '+rel);bad.append(rel)
print(f"8.1.43 runtime freeze: {len(doc['files'])-len(bad)}/{len(doc['files'])} passed")
sys.exit(1 if bad else 0)
