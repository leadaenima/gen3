#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1];doc=json.loads((R/'tools/baselines/8.1.64-runtime-sha256.json').read_text());bad=[]
for rel,exp in doc['files'].items():
 p=R/rel
 if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest()!=exp['sha256'] or p.stat().st_size!=exp['size']:
  print('FAIL changed '+rel);bad.append(rel)
print(f"8.1.64 runtime freeze: {len(doc['files'])-len(bad)}/{len(doc['files'])} passed")
sys.exit(1 if bad else 0)
