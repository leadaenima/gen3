#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys,re
R=Path(__file__).resolve().parents[1]
sp=(R/'lib/SnowPack.lua').read_text()
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text()
checks=[]
def ck(v,msg): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+msg)
ck('PATCH_RADIUS_MAX = 9.75' in sp,'mature snow-bank radius expands to 9.75 world units')
ck('PATCH_MERGE_DISTANCE = 5.80' in sp,'nearby snow deposits use explicit merge distance')
ck('MAX_GROUND_HEIGHT = 3.60' in sp and 'MAX_GRASS_HEIGHT = 3.20' in sp and 'MAX_WALKTHROUGH_HEIGHT' not in sp,'8.1.67 accumulation height profile is preserved exactly')
ck('function coalesceAggregate(ctx,p)' in sp and 'SP.coalesceAggregate=coalesceAggregate' in sp,'SnowPack owns executable aggregate-bank coalescing')
ck('sqrt(pr*pr+qr*qr)' in sp,'coalescing preserves area while widening the bank')
ck('if p and not snowActive then' in sp,'footsteps do not remove persistent snow mass during active snowfall')
ck('((qn%9)-4)*4' not in wp and '9x9 interaction lattice' not in wp,'old line-forming 9x9 deposition lattice is absent')
ck('2.399963229728653' in wp,'distributed aggregate sampler uses golden-angle placement')
ck('_snowPackStormAge/45' in wp,'accumulation ramps over the first 45 seconds')
ck('min(18,max(2.0,snowI*3.6))' in wp,'aggregate support sampling is capped at 18 samples/second')
ck('local radius=4+sqrt(v)*108' in wp,'aggregate samples spread across a broad 4-112 world-unit disk')
ck('local i1=r1*0.72' in wp,'bank mesh uses a broad flat interior rather than a narrow dome')
ck('edgeY=baseY+min(h*0.22,0.34)' in wp,'bank perimeter uses one restrained soft slope')
r=subprocess.run(['texlua',str(R/'tests/snow_bank_distribution_8168_test.lua'),str(R)],cwd=R)
ck(r.returncode==0,'executable distributed/coalescing snow-bank regression')
print(f'8.1.68 snow-bank contract: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
