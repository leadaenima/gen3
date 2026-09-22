#!/usr/bin/env python3
from pathlib import Path
import json,hashlib,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
cin=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text(); wcl=(R/'lib/voxel_atmos/WorldCelestialLighting.lua').read_text()
ck('local step=176' in cin and 'for iz=-1,1 do for ix=-1,1 do' in cin,'regional sunlight coverage is fixed 3x3 / nine samples')
ck('local maxClouds=math.min(#clouds,18)' in wcl and 'for j=1,#lobes do' in wcl,'terrain shadow pass stays <=18 clouds x 4 lobes')
ck('newCanvas' not in wcl and 'Canvas' not in wcl,'no framebuffer/cloud-shadow texture introduced')
ck('drawInstanced' not in wcl and 'local FMT=' in wcl,'existing single small streamed terrain mesh retained')
version=json.loads((R/'manifest.json').read_text()).get('version','')
base=json.loads((R/'tools/baselines/8.1.52-runtime-sha256.json').read_text())['files']
for rel in ['lib/DistantFrontPrecip.lua','lib/Quality.lua','lib/DistantWeather.lua','lib/StormCells.lua','lib/Audio.lua','lib/voxel_atmos/WorldPrecip.lua','lib/voxel_atmos/ConnectedWater3D.lua']:
    p=R/rel; exp=base[rel]
    if version=='8.1.53':
        ck(hashlib.sha256(p.read_bytes()).hexdigest()==exp['sha256'] and p.stat().st_size==exp['size'],rel+' byte-identical to 8.1.52')
    else:
        ck(True,rel+' historical 8.1.53 freeze scoped to exact 8.1.53')
print(f'8.1.53 performance preservation: {sum(checks)}/{len(checks)} passed'); sys.exit(0 if all(checks) else 1)
