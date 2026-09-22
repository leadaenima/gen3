#!/usr/bin/env python3
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1];c=[]
def ck(v,m): c.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.60','manifest 8.1.60')
ck((R/'BASELINE').read_text().strip()=='8.1.60','BASELINE 8.1.60')
for f in [
 'RELEASE-NOTES-8.1.60.md','lib/NpcLightning2D.lua','tests/npc_lightning_2d_8160_test.lua',
 'tools/test_8160_runtime_delta.py','tools/test_8160_runtime_freeze.py','tools/test_8160_package_surface.py',
 'tools/test_8160_npc_lightning_contract.py','tools/baselines/8.1.60-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
ck('2D NPC Lightning' in (R/'CHANGELOG.md').read_text()[:500],'changelog 8.1.60 entry')
ck('2D NPC Lightning' in (R/'README.md').read_text()[:500],'README 8.1.60 entry')
print(f'8.1.60 package surface: {sum(c)}/{len(c)} passed')
sys.exit(0 if all(c) else 1)
