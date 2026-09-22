#!/usr/bin/env python3
from pathlib import Path
import os,sys
root=os.environ.get('VOXEL_NEXUS_ROOT') or (sys.argv[1] if len(sys.argv)>1 else '')
if not root:
    print('SKIP 8.1.45 exact Voxel Nexus contract: supply VOXEL_NEXUS_ROOT or path');sys.exit(0)
R=Path(root);checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
def read(rel):
    p=R/rel;ck(p.exists(),rel+' exists');return p.read_text(errors='replace') if p.exists() else ''
w=read('lib/Water.lua');vs=read('lib/VoxelScene.lua');we=read('lib/realistic/WaterEngine.lua')
ck('Water.WAVE_HEIGHT = 5' in w,'Nexus native water has 5px geometric relief')
ck('Water._trainSource' in w,'Nexus structured water exports _trainSource discriminator')
for token in ('function Water.begin','function Water.draw','function Water.finish'):
    ck(token in w,'Nexus reflective water exposes '+token.split()[-1])
ck('function VoxelScene.drawWater' in vs,'Nexus VoxelScene owns a late water pass')
ck('Voxel3D.draw(d[1], d[2], d[3])' in vs,'curved Nexus path depth-draws raw water model before reflection')
ck('Water.draw(d[1], d[2], d[3])' in vs,'Nexus reflective path submits same water row through Water.draw')
ck('original.draw' in we and 'composeTide(model)' in we,'Nexus realistic WaterEngine wraps native Water.draw with composed tide model')
ck('function M.tideOffset' in we,'Nexus realistic WaterEngine publishes tideOffset seam')
failed=sum(not v for v,_ in checks);print(f'8.1.45 exact Voxel Nexus source contract: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
