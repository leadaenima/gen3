#!/usr/bin/env python3
from pathlib import Path
import json,re,sys
R=Path(__file__).resolve().parents[1]; checks=[]
def ck(v,m): checks.append(bool(v)); print(('PASS ' if v else 'FAIL ')+m)
man=json.loads((R/'manifest.json').read_text())
ck(man.get('version')=='8.1.50','manifest 8.1.50')
ck((R/'BASELINE').read_text().strip()=='8.1.50','BASELINE 8.1.50')
for f in [
 'RELEASE-NOTES-8.1.50.md','FRONT-PRECIP-CONTINUITY-AUDIT-8.1.50.md',
 'tools/test_8150_runtime_delta.py','tools/test_8150_runtime_freeze.py','tools/test_8150_package_surface.py',
 'tests/front_precip_continuity_8150_test.lua',
 'tools/baselines/8.1.49-runtime-sha256.json','tools/baselines/8.1.50-runtime-sha256.json']:
    ck((R/f).exists(),f+' present')
d=(R/'lib/DistantWeather.lua').read_text(); c=(R/'lib/voxel_atmos/CinematicAtmos.lua').read_text()
ck('radius*.62' in d and 'shaftHandoff' in d,'broad 62% remote/local hydrometeor overlap present')
ck('painted rain/snow curtain' in c and 'particleQuad' in c,'discrete 3D front particle implementation present')
ck('particleBudget=math.max(1400,math.floor(9000*qscale+.5))' in c,'remote particle budget is quality-scaled and bounded')
ck('kind==0' in c and 'kind==3' in c,'rain/snow/blizzard particle branches present')
# No hydrometeor front path may call the old card renderer for rain/snow/blizzard.
segment=c[c.find('if alpha>.004 then'):c.find('-- A remote charged cloud owns',c.find('if alpha>.004 then'))]
ck('if kind==2 then' in segment and 'card(' in segment and 'particleQuad(' in segment,'fog-only card branch plus particle hydrometeor branch present')
# Preserve the professional settings surface from 8.1.49.
s=(R/'lib/Settings.lua').read_text(); sm=(R/'lib/SettingsMenu.lua').read_text()
schema=s[s.find('Settings.SCHEMA'):s.find('Settings.GROUPS')]
keys=re.findall(r'key\s*=\s*"([A-Za-z0-9_]+)"',schema)
ck(len(keys)==68 and len(set(keys))==68,'68-setting player surface preserved')
groups=s[s.find('Settings.GROUPS'):s.find('function Settings.row',s.find('Settings.GROUPS'))]
group_ids=re.findall(r'\{\s*id="([^"]+)"',groups)
ck(len(group_ids)==11 and len(set(group_ids))==11,'11 shallow categories preserved')
rn=(R/'RELEASE-NOTES-8.1.50.md').read_text(); audit=(R/'FRONT-PRECIP-CONTINUITY-AUDIT-8.1.50.md').read_text()
ck('1,626' in rn and '8,819' in rn and '8,841' in rn and '49,702' in rn,'real rain/snow overlap counts documented')
ck('negative-control' in audit and '6 of 9' in audit,'negative-control test evidence documented')
print(f'8.1.50 package surface: {sum(checks)}/{len(checks)} passed')
sys.exit(0 if all(checks) else 1)
