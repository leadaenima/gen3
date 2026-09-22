#!/usr/bin/env python3
from pathlib import Path
import os,sys,re
root=os.environ.get('VOXEL_NEXUS_ROOT') or (sys.argv[1] if len(sys.argv)>1 else '')
if not root:
    print('SKIP 8.1.46 exact Voxel Nexus continuity contract: supply VOXEL_NEXUS_ROOT or path');sys.exit(0)
R=Path(root);checks=[]
def ck(v,m): checks.append((bool(v),m));print(('PASS ' if v else 'FAIL ')+m)
def read(rel):
    p=R/rel;ck(p.exists(),rel+' exists');return p.read_text(errors='replace') if p.exists() else ''
w=read('lib/Water.lua');vs=read('lib/VoxelScene.lua')
ck('function Water.begin(ctx, skyOnly)' in w,'Nexus Water exposes explicit SKY-only material mode')
ck('if not skyOnly and not (ctx.reflect and ctx.depth) then return false end' in w,'SKY-only does not require reflected-frame/depth textures')
ck('if skyOnly then' in w and 'Sky.ramp()' in w,'SKY-only still resolves the live sky ramp')
ck('send("fresnelFloor"' in w and 'send("fresnelCeil"' in w and 'send("fresnelPower"' in w,'SKY-only shares the native Fresnel material controls')
ck('send("waveSlope"' in w and 'send("waveT"' in w,'SKY-only shares live wave-normal phase controls')
ck('Water.sendSky(sh, ctx)' in w,'SKY-only shares sun/moon/sky optical uniforms')
ck('if not skyOnly then send("rays"' in w,'FULL SSR ray march is excluded from SKY-only shader mode')
ck('Water.begin(waterContext(nil, nil), true)' in vs,'Nexus VoxelScene itself uses SKY-only as its proven lightweight water fallback')
ck('Voxel3D.endWater()' in vs,'Nexus restores scene shader/depth state after SKY-only fallback')
ck('Voxel3D.beginWater(cast)' in vs,'FULL path separately owns framebuffer/depth copy')
failed=sum(not v for v,_ in checks);print(f'8.1.46 exact Voxel Nexus continuity source contract: {len(checks)-failed}/{len(checks)} passed');sys.exit(1 if failed else 0)
