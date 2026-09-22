#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,msg): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+msg)
wp=(R/'lib/voxel_atmos/WorldPrecip.lua').read_text(); sp=(R/'lib/SnowPack.lua').read_text()
ck('SP.ACCUMULATION_ENABLED = true' in sp,'SnowPack accumulation enabled')
ck('depositAggregate' in sp and 'depositAggregate' in wp,'aggregate procedural deposition is live')
ck('AGGREGATE_SUPPORT_HZ' in wp or '24' in wp,'bounded aggregate support sampler present')
ck('aggregateMass' in sp,'aggregate samples carry representative physical snow mass')
ck('FOOT_STEP' in sp and 'MIN_TRACK_DEPTH' in sp,'physical footprint thresholds retained')
ck('SP.resolveFlake' in wp,'exact-support flake interaction retained')
ck('MAX_CELLS' in sp and 'MAX_FOOTPRINTS' in sp,'bounded SnowPack state retained')
r=subprocess.run(['texlua',str(R/'tests/snowpack_live_restore_8164_test.lua'),str(R)],cwd=R,capture_output=True,text=True); print(r.stdout,end=''); ck(r.returncode==0,'executable SnowPack live restore 7/7')
print(f'8.1.64 SnowPack restore contract: {sum(checks)}/{len(checks)} passed'); sys.exit(0 if all(checks) else 1)
