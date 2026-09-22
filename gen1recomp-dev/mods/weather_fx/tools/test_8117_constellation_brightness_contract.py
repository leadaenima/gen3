#!/usr/bin/env python3
"""Weather FX 8.1.17 constellation midpoint-brightness regression."""
from pathlib import Path
import json,sys
R=Path(__file__).resolve().parents[1]
con=(R/'lib/Constellations.lua').read_text()
ns=(R/'lib/NightSky.lua').read_text()
man=json.loads((R/'manifest.json').read_text())
checks=[]
def ck(v,msg):
    checks.append((bool(v),msg)); print(('PASS ' if v else 'FAIL ')+msg)
ck(tuple(map(int,man.get('version','0.0.0').split('.'))) >= (8,1,17),'manifest is 8.1.17 or newer')
ck(tuple(map(int,(R/'BASELINE').read_text().strip().split('.'))) >= (8,1,17),'baseline is 8.1.17 or newer')
ck('a=primary and .96 or .73' in con,'unified constellation alpha is exact old/new midpoint (.96/.73)')
ck('a=primary and 1.00 or .84' not in con,'8.1.16 extra-bright constellation alpha removed')
ck('buildingScale=math.max' in con and '*fade*buildingScale*' in con,'world constellations retain smooth building dimming')
ck('local function constellationBuildingScale()' in ns and '*constVis*constBuilding*' in ns,'projected constellations retain BuildingLight response')
failed=sum(not v for v,_ in checks)
print(f'8.1.17 constellation brightness contract: {len(checks)-failed}/{len(checks)} passed, {failed} failed')
sys.exit(1 if failed else 0)
