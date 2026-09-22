#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
R=Path(__file__).resolve().parents[1]
eng=(R/'lib/CelestialEngine.lua').read_text()
cin=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
wcl=(R/'lib/voxel_atmos/WorldCelestialLighting.lua').read_text()
checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
ck('A single player-space hole in the cloud' in eng and 'direct=direct*lerp(0.20,1,localT)' not in eng,'player-local cloud transmission removed from map-wide direct light')
ck('CinematicAtmos._regionalCloudCoverage' in cin and 'E.observeCloudField(tr,regional)' in cin,'regional descriptor coverage feeds world-light observer')
ck('for iz=-1,1 do for ix=-1,1 do' in cin and 'local step=176' in cin,'regional coverage uses bounded 3x3 spatial footprint')
ck('Match the same four macro lobes used by CinematicAtmos cloud occlusion' in wcl,'terrain cloud mask follows visible macro cloud bodies')
ck('local maxClouds=math.min(#clouds,18)' in wcl and 'for j=1,#lobes do' in wcl,'terrain mask remains bounded on low-end hardware')
rc=subprocess.call(['texlua',str(R/'tests/cloud_sun_localization_8153_test.lua')],cwd=R)
ck(rc==0,'executable cloud/sun localisation regression')
print(f'8.1.53 cloud sun localisation: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
