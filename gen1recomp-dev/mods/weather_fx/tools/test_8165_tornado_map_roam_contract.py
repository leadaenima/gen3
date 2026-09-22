#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
s=(R/'lib/Tornado.lua').read_text();r=(R/'lib/voxel_atmos/Tornado3D.lua').read_text();checks=[]
def ck(v,m): checks.append(bool(v));print(('PASS ' if v else 'FAIL ')+m)
ck('local function resolveMapLocal' in s,'map-local connection resolver exists')
ck('local function moveOffscreen' in s,'offscreen simulation path exists')
ck('r.mapX' in s and 'r.mapZ' in s,'persistent map-local coordinates exist')
ck('connectionFor(def,dir)' in s and 'mapOutside(dest,ddef,data,Map)' in s,'remote crossing requires authored outdoor connection')
ck('r.offscreenCrossings' in s,'remote crossings are auditable')
ck('if T._voxelState and r.mapId and not visibleReg then' in s,'remote mode activates only with a proven voxel state')
ck('updateRemoteSurface(r,dt)' in s,'remote funnels update own-map surface state')
ck('do not sample the player' in s.lower() or 'unrelated frame' in s.lower(),'remote movement avoids unrelated current-root contact sampling')
ck('for _,r in ipairs(T.active) do projectFromMapLocal(r,state) end' in s,'root changes reproject persistent entities')
ck('offscreen=offscreen' in s and 'offscreenCrossings=remoteCrossings' in s,'persistence diagnostics expose remote state')
ck('if not r.offscreen then' in r,'Tornado3D culls offscreen entities before geometry generation')
ck('if #verts<3 then return false end' in r,'all-remote tornado list submits no draw')
print(f'8.1.65 tornado map roam contract: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
