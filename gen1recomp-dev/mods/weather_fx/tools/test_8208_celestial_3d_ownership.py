#!/usr/bin/env python3
from pathlib import Path
import sys
R=Path(__file__).resolve().parents[1]
a=(R/'lib/DramalessAtmos.lua').read_text(); s=(R/'lib/Settings.lua').read_text(); c=(R/'lib/CelestialEngine.lua').read_text()
checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
ck('if want3d() then return true end' in a,'active 3D weather forces world-space celestial ownership')
ck('if Settings.force3dPresent and Settings.force3dPresent() then return true end' in s,'explicit 3D weather cannot be overridden by CELESTIAL RENDERING = 2D')
ck(a.find('drawWorldCelestial()') < a.find('cin.draw'), 'celestial vault is submitted before cloud/weather geometry')
ck('geometryCloudOcclusion=type(localT)=="number"' in c,'3D cloud observation selects geometry occlusion mode')
ck('cloudLineTransmission=optics.localCloudTransmission' in c,'coarse cloud ray remains separate for direct optics')
ck('geometryCloudOcclusion and 1 or (1-optics.cloud*0.92)' in c,'3D clouds no longer globally fade stars/constellations')
print(f'8.2.8 3D celestial ownership: {sum(checks)}/{len(checks)} PASS')
sys.exit(0 if all(checks) else 1)
