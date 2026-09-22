#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
p=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
night=(R/'lib/NightSky.lua').read_text()
checks=[]
def ck(v,m):
    checks.append((bool(v),m)); print(('PASS ' if v else 'FAIL ')+m)
ck('local projected = nx ~= nil and ny ~= nil' in p,'cloud projection validity is explicit')
ck('if overheadDeck or projected then' in p,'overhead deck can survive failed projection')
ck('if overheadDeck or (projected and nx > -2.10' in p,'frustum math only runs with projection')
ck('local screenY = projected and (ny * 0.5 + 0.5) or 0.06' in p,'screenY has projection-safe overhead fallback')
ck('local desirability = projected' in p,'desirability does not do arithmetic on nil nx/ny')
ck('uniform float cloudCover;' not in p,'dead puddle cloudCover uniform removed')
ck('sh, "cloudCover"' not in p,'dead puddle cloudCover send removed')
ck('cloudMeshCapacity' in p and 'while cap < need do cap = cap * 2 end' in p,'fallback cloud mesh grows before larger weather populations upload')
ck('cloudMesh.setVertices, cloudMesh, verts, 1, need' in p,'fallback cloud upload uses bounded current vertex count')
ck('function CinematicAtmos._uploadStreamMesh' in p,'weather-dependent fallback stream meshes share grow-only uploader')
ck('CinematicAtmos._uploadStreamMesh("rain"' in p,'rain fallback can grow as intensity eases upward')
ck('CinematicAtmos._uploadStreamMesh("mist"' in p and 'CinematicAtmos._uploadStreamMesh("rays"' in p,'fog/ray fallback meshes can grow across weather/time transitions')
# Keep weather coverage authority elsewhere; this repair must not globally delete coverage use.
ck('vBodyUV = VertexTexCoord.xy;' in night,'projected celestial shader uses LÖVE-11.5-compatible vec2 texcoord swizzle')
ck(p.count('coverage') > 20,'weather coverage logic remains present elsewhere')
failed=sum(not ok for ok,_ in checks)
print(f'8.1.27 live-host repairs: {len(checks)-failed}/{len(checks)} passed')
sys.exit(1 if failed else 0)
